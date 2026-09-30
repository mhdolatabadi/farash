package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type projectsStore interface {
	EnsureInboxProject(context.Context, string) (store.Project, error)
	ListProjects(context.Context, string) ([]store.Project, error)
	CreateProject(context.Context, string, store.ProjectInput) (store.Project, error)
	UpdateProject(context.Context, string, string, store.ProjectUpdate) (store.Project, error)
	DeleteProject(context.Context, string, string) error
}

type projectsHandler struct {
	auth  *authHandler
	store projectsStore
}

type projectRequest struct {
	ParentID   *string `json:"parent_id"`
	Name       string  `json:"name"`
	Color      string  `json:"color"`
	SortOrder  int     `json:"sort_order"`
	IsFavorite bool    `json:"is_favorite"`
	Kind       string  `json:"kind"`
}

type projectPatchRequest struct {
	ParentID   *string `json:"parent_id"`
	Name       *string `json:"name"`
	Color      *string `json:"color"`
	SortOrder  *int    `json:"sort_order"`
	IsFavorite *bool   `json:"is_favorite"`
	IsArchived *bool   `json:"is_archived"`
	Kind       *string `json:"kind"`
}

func newProjectsHandler(auth *authHandler, store projectsStore) *projectsHandler {
	return &projectsHandler{auth: auth, store: store}
}

func (h *projectsHandler) list(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	projects, err := h.store.ListProjects(r.Context(), user.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "projects_list_failed")
		return
	}
	writeJSON(w, http.StatusOK, map[string][]store.Project{"projects": projects})
}

func (h *projectsHandler) create(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	request, ok := decodeProjectRequest[projectRequest](w, r)
	if !ok {
		return
	}
	if strings.TrimSpace(request.Name) == "" {
		writeError(w, http.StatusBadRequest, "invalid_project_name")
		return
	}
	project, err := h.store.CreateProject(r.Context(), user.ID, store.ProjectInput{ParentID: request.ParentID, Name: request.Name, Color: request.Color, SortOrder: request.SortOrder, IsFavorite: request.IsFavorite, Kind: request.Kind})
	if err != nil {
		writeError(w, http.StatusBadRequest, "project_create_failed")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]store.Project{"project": project})
}

func (h *projectsHandler) update(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	request, ok := decodeProjectRequest[projectPatchRequest](w, r)
	if !ok {
		return
	}
	project, err := h.store.UpdateProject(r.Context(), user.ID, r.PathValue("id"), store.ProjectUpdate{ParentID: request.ParentID, Name: request.Name, Color: request.Color, SortOrder: request.SortOrder, IsFavorite: request.IsFavorite, IsArchived: request.IsArchived, Kind: request.Kind})
	if err != nil {
		writeProjectError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]store.Project{"project": project})
}

func (h *projectsHandler) delete(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	if err := h.store.DeleteProject(r.Context(), user.ID, r.PathValue("id")); err != nil {
		writeProjectError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func decodeProjectRequest[T any](w http.ResponseWriter, r *http.Request) (T, bool) {
	defer r.Body.Close()
	var request T
	if err := json.NewDecoder(r.Body).Decode(&request); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return request, false
	}
	return request, true
}

func writeProjectError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, store.ErrProjectNotFound):
		writeError(w, http.StatusNotFound, "project_not_found")
	case errors.Is(err, store.ErrInboxProject):
		writeError(w, http.StatusConflict, "inbox_project")
	default:
		writeError(w, http.StatusInternalServerError, "project_write_failed")
	}
}
