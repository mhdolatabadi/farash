package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

const maxJSONBodyBytes = 16 << 10

// ProjectColors are the colors a project can have, as in Todoist.
var ProjectColors = map[string]bool{
	"berry_red": true, "red": true, "orange": true, "yellow": true,
	"olive_green": true, "lime_green": true, "green": true, "mint_green": true,
	"teal": true, "sky_blue": true, "light_blue": true, "blue": true,
	"grape": true, "violet": true, "lavender": true, "magenta": true,
	"salmon": true, "charcoal": true, "grey": true, "taupe": true,
}

const defaultProjectColor = "charcoal"

type projectStore interface {
	Projects(ctx context.Context, ownerID string, archived bool) ([]store.Project, error)
	Project(ctx context.Context, ownerID, id string) (store.Project, error)
	CreateProject(ctx context.Context, ownerID string, input store.NewProject) (store.Project, error)
	UpdateProject(ctx context.Context, ownerID, id string, changes store.ProjectChanges) (store.Project, error)
	DeleteProject(ctx context.Context, ownerID, id string) error
	ReorderProjects(ctx context.Context, ownerID string, ids []string) error
}

type projectHandler struct {
	auth     *authHandler
	projects projectStore
}

func (h *projectHandler) routes(mux *http.ServeMux) {
	mux.HandleFunc("GET /api/v1/projects", h.list)
	mux.HandleFunc("POST /api/v1/projects", h.create)
	mux.HandleFunc("POST /api/v1/projects/reorder", h.reorder)
	mux.HandleFunc("GET /api/v1/projects/{id}", h.get)
	mux.HandleFunc("PATCH /api/v1/projects/{id}", h.update)
	mux.HandleFunc("DELETE /api/v1/projects/{id}", h.delete)
}

type projectResponse struct {
	ID         string    `json:"id"`
	ParentID   *string   `json:"parentId"`
	Name       string    `json:"name"`
	Color      string    `json:"color"`
	IsInbox    bool      `json:"isInbox"`
	IsFavorite bool      `json:"isFavorite"`
	IsArchived bool      `json:"isArchived"`
	ChildOrder int       `json:"childOrder"`
	CreatedAt  time.Time `json:"createdAt"`
	UpdatedAt  time.Time `json:"updatedAt"`
}

func toProjectResponse(p store.Project) projectResponse {
	return projectResponse{
		ID: p.ID, ParentID: p.ParentID, Name: p.Name, Color: p.Color,
		IsInbox: p.IsInbox, IsFavorite: p.IsFavorite, IsArchived: p.IsArchived,
		ChildOrder: p.ChildOrder, CreatedAt: p.CreatedAt.UTC(), UpdatedAt: p.UpdatedAt.UTC(),
	}
}

func (h *projectHandler) list(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	archived := r.URL.Query().Get("archived") == "true"
	projects, err := h.projects.Projects(r.Context(), user.ID, archived)
	if err != nil {
		internalError(w, "list projects", err)
		return
	}
	body := make([]projectResponse, len(projects))
	for i, p := range projects {
		body[i] = toProjectResponse(p)
	}
	writeJSON(w, http.StatusOK, map[string][]projectResponse{"projects": body})
}

func (h *projectHandler) get(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	project, err := h.projects.Project(r.Context(), user.ID, r.PathValue("id"))
	if err != nil {
		writeProjectError(w, "get project", err)
		return
	}
	writeJSON(w, http.StatusOK, toProjectResponse(project))
}

type createProjectRequest struct {
	Name       string  `json:"name"`
	Color      string  `json:"color"`
	ParentID   *string `json:"parentId"`
	IsFavorite bool    `json:"isFavorite"`
}

func (h *projectHandler) create(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	var request createProjectRequest
	if !decodeJSON(w, r, &request) {
		return
	}
	name, ok := validProjectName(request.Name)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid_name")
		return
	}
	color := request.Color
	if color == "" {
		color = defaultProjectColor
	}
	if !ProjectColors[color] {
		writeError(w, http.StatusBadRequest, "invalid_color")
		return
	}
	project, err := h.projects.CreateProject(r.Context(), user.ID, store.NewProject{
		Name: name, Color: color, ParentID: request.ParentID, IsFavorite: request.IsFavorite,
	})
	if err != nil {
		writeProjectError(w, "create project", err)
		return
	}
	writeJSON(w, http.StatusCreated, toProjectResponse(project))
}

// update takes any of name, color, isFavorite, isArchived and parentId;
// "parentId": null moves the project to the top level.
func (h *projectHandler) update(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	var fields map[string]json.RawMessage
	if !decodeJSON(w, r, &fields) {
		return
	}
	var changes store.ProjectChanges
	for key, raw := range fields {
		var err error
		switch key {
		case "name":
			var name string
			if err = json.Unmarshal(raw, &name); err == nil {
				trimmed, valid := validProjectName(name)
				if !valid {
					writeError(w, http.StatusBadRequest, "invalid_name")
					return
				}
				changes.Name = &trimmed
			}
		case "color":
			var color string
			if err = json.Unmarshal(raw, &color); err == nil {
				if !ProjectColors[color] {
					writeError(w, http.StatusBadRequest, "invalid_color")
					return
				}
				changes.Color = &color
			}
		case "isFavorite":
			err = unmarshalNonNull(raw, &changes.IsFavorite)
		case "isArchived":
			err = unmarshalNonNull(raw, &changes.IsArchived)
		case "parentId":
			changes.MoveParent = true
			err = json.Unmarshal(raw, &changes.ParentID)
		default:
			writeError(w, http.StatusBadRequest, "unknown_field")
			return
		}
		if err != nil {
			writeError(w, http.StatusBadRequest, "invalid_json")
			return
		}
	}
	project, err := h.projects.UpdateProject(r.Context(), user.ID, r.PathValue("id"), changes)
	if err != nil {
		writeProjectError(w, "update project", err)
		return
	}
	writeJSON(w, http.StatusOK, toProjectResponse(project))
}

func (h *projectHandler) delete(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	if err := h.projects.DeleteProject(r.Context(), user.ID, r.PathValue("id")); err != nil {
		writeProjectError(w, "delete project", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type reorderRequest struct {
	IDs []string `json:"ids"`
}

func (h *projectHandler) reorder(w http.ResponseWriter, r *http.Request) {
	user, ok := h.auth.authenticate(w, r)
	if !ok {
		return
	}
	var request reorderRequest
	if !decodeJSON(w, r, &request) {
		return
	}
	if len(request.IDs) == 0 || len(request.IDs) > 500 {
		writeError(w, http.StatusBadRequest, "invalid_order")
		return
	}
	if err := h.projects.ReorderProjects(r.Context(), user.ID, request.IDs); err != nil {
		writeProjectError(w, "reorder projects", err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func writeProjectError(w http.ResponseWriter, action string, err error) {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found")
	case errors.Is(err, store.ErrInboxProtected):
		writeError(w, http.StatusBadRequest, "inbox_protected")
	case errors.Is(err, store.ErrInvalidParent):
		writeError(w, http.StatusBadRequest, "invalid_parent")
	case errors.Is(err, store.ErrInvalidOrder):
		writeError(w, http.StatusBadRequest, "invalid_order")
	default:
		internalError(w, action, err)
	}
}

// validProjectName trims the name and allows 1–120 characters on one line.
func validProjectName(raw string) (string, bool) {
	name := strings.TrimSpace(raw)
	length := utf8.RuneCountInString(name)
	if length == 0 || length > 120 || strings.ContainsAny(name, "\r\n") || !utf8.ValidString(name) {
		return "", false
	}
	return name, true
}

// decodeJSON reads a size-limited JSON body into target, rejecting unknown
// fields and trailing data.
func decodeJSON(w http.ResponseWriter, r *http.Request, target any) bool {
	defer r.Body.Close()
	decoder := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxJSONBodyBytes))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(target); err != nil || decoder.More() {
		writeError(w, http.StatusBadRequest, "invalid_json")
		return false
	}
	return true
}

func unmarshalNonNull[T any](raw json.RawMessage, target **T) error {
	if bytes.Equal(bytes.TrimSpace(raw), []byte("null")) {
		return errors.New("null is not allowed")
	}
	var value T
	if err := json.Unmarshal(raw, &value); err != nil {
		return err
	}
	*target = &value
	return nil
}

// internalError logs the cause without request data, so task content never
// reaches the logs.
func internalError(w http.ResponseWriter, action string, err error) {
	slog.Error("request failed", "action", action, "error", err)
	writeError(w, http.StatusInternalServerError, "internal_error")
}
