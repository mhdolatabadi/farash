package httpapi

import (
	"context"
	"net/http"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type labelsStore interface {
	ListLabels(context.Context, string) ([]store.Label, error)
	CreateLabel(context.Context, string, store.LabelInput) (store.Label, error)
	UpdateLabel(context.Context, string, string, store.LabelUpdate) (store.Label, error)
	DeleteLabel(context.Context, string, string) error
}

type labelsHandler struct {
	auth *authHandler
	data labelsStore
}

func (h *labelsHandler) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/labels", h.list)
	mux.HandleFunc("POST /api/v1/labels", h.create)
	mux.HandleFunc("PATCH /api/v1/labels/{id}", h.update)
	mux.HandleFunc("DELETE /api/v1/labels/{id}", h.delete)
}

func (h *labelsHandler) list(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	labels, err := h.data.ListLabels(r.Context(), user.ID)
	if err != nil {
		writeTaskError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string][]store.Label{"labels": labels})
}

func (h *labelsHandler) create(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	input, ok := decodeTaskRequest[store.LabelInput](w, r)
	if !ok {
		return
	}
	label, err := h.data.CreateLabel(r.Context(), user.ID, input)
	if err != nil {
		writeTaskError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]store.Label{"label": label})
}

func (h *labelsHandler) update(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	input, ok := decodeTaskRequest[store.LabelUpdate](w, r)
	if !ok {
		return
	}
	label, err := h.data.UpdateLabel(r.Context(), user.ID, r.PathValue("id"), input)
	if err != nil {
		writeTaskError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]store.Label{"label": label})
}

func (h *labelsHandler) delete(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	if err := h.data.DeleteLabel(r.Context(), user.ID, r.PathValue("id")); err != nil {
		writeTaskError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
