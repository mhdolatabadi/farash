package httpapi

import (
	"context"
	"errors"
	"net/http"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type sectionsStore interface {
	ListSections(context.Context, string, string) ([]store.Section, error)
	CreateSection(context.Context, string, store.SectionInput) (store.Section, error)
	UpdateSection(context.Context, string, string, store.SectionUpdate) (store.Section, error)
	DeleteSection(context.Context, string, string, bool) error
	ReorderSections(context.Context, string, string, []string) error
}

type sectionsHandler struct {
	auth *authHandler
	data sectionsStore
}

func (h *sectionsHandler) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/sections", h.list)
	mux.HandleFunc("POST /api/v1/sections", h.create)
	mux.HandleFunc("POST /api/v1/sections/reorder", h.reorder)
	mux.HandleFunc("PATCH /api/v1/sections/{id}", h.update)
	mux.HandleFunc("DELETE /api/v1/sections/{id}", h.delete)
}

func (h *sectionsHandler) list(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	project := r.URL.Query().Get("projectId")
	if project == "" {
		writeError(w, http.StatusBadRequest, "project_id_required")
		return
	}
	sections, err := h.data.ListSections(r.Context(), user.ID, project)
	if err != nil {
		writeTaskError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string][]store.Section{"sections": sections})
}

func (h *sectionsHandler) create(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	input, ok := decodeTaskRequest[store.SectionInput](w, r)
	if !ok {
		return
	}
	if input.ProjectID == "" {
		writeError(w, http.StatusBadRequest, "project_id_required")
		return
	}
	section, err := h.data.CreateSection(r.Context(), user.ID, input)
	if err != nil {
		writeTaskError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]store.Section{"section": section})
}

func (h *sectionsHandler) update(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	input, ok := decodeTaskRequest[store.SectionUpdate](w, r)
	if !ok {
		return
	}
	section, err := h.data.UpdateSection(r.Context(), user.ID, r.PathValue("id"), input)
	if err != nil {
		writeTaskError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]store.Section{"section": section})
}

func (h *sectionsHandler) delete(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	deleteTasks := r.URL.Query().Get("deleteTasks")
	if deleteTasks != "" && deleteTasks != "true" && deleteTasks != "false" {
		writeError(w, http.StatusBadRequest, "invalid_delete_tasks")
		return
	}
	if err := h.data.DeleteSection(r.Context(), user.ID, r.PathValue("id"), deleteTasks == "true"); err != nil {
		writeTaskError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (h *sectionsHandler) reorder(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	input, ok := decodeTaskRequest[struct {
		ProjectID  string   `json:"project_id"`
		SectionIDs []string `json:"section_ids"`
	}](w, r)
	if !ok {
		return
	}
	if input.ProjectID == "" {
		writeError(w, http.StatusBadRequest, "project_id_required")
		return
	}
	if err := h.data.ReorderSections(r.Context(), user.ID, input.ProjectID, input.SectionIDs); err != nil {
		writeTaskError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// writeSectionError maps section errors; it returns false for other errors.
func writeSectionError(w http.ResponseWriter, err error) bool {
	switch {
	case errors.Is(err, store.ErrSectionNotFound):
		writeError(w, http.StatusNotFound, "section_not_found")
	case errors.Is(err, store.ErrInvalidSection):
		writeError(w, http.StatusBadRequest, "invalid_section")
	default:
		return false
	}
	return true
}
