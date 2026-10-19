package httpapi

import (
	"context"
	"errors"
	"github.com/mhdolatabadi/farash/server/internal/store"
	"net/http"
)

type agileStore interface {
	AgileWorkspace(context.Context, string, string) (store.AgileWorkspace, error)
	AgileWrite(context.Context, string, string, string, string, store.AgileCommand) error
}

func agileRoutes(mux *http.ServeMux, auth *authHandler, data agileStore) {
	handler := func(action string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			user, ok := auth.authenticate(w, r)
			if !ok {
				return
			}
			project := r.PathValue("project")
			var err error
			if action != "read" {
				in, ok := decodeTaskRequest[store.AgileCommand](w, r)
				if !ok {
					return
				}
				err = data.AgileWrite(r.Context(), user.ID, project, action, r.PathValue("id"), in)
			}
			var result store.AgileWorkspace
			if err == nil {
				result, err = data.AgileWorkspace(r.Context(), user.ID, project)
			}
			if err != nil {
				switch {
				case errors.Is(err, store.ErrAgileNotFound):
					writeError(w, 404, "not_found")
				case errors.Is(err, store.ErrAgileInvalid):
					writeError(w, 400, "invalid_agile_input")
				case errors.Is(err, store.ErrAgileConflict):
					writeError(w, 409, "agile_state_conflict")
				default:
					writeError(w, 500, "agile_unavailable")
				}
				return
			}
			writeJSON(w, 200, result)
		}
	}
	base := "/api/v1/projects/{project}/agile"
	mux.HandleFunc("GET "+base, handler("read"))
	mux.HandleFunc("PATCH "+base, handler("method"))
	mux.HandleFunc("PUT "+base+"/items/{id}", handler("item"))
	mux.HandleFunc("POST "+base+"/sprints", handler("create"))
	mux.HandleFunc("PATCH "+base+"/sprints/{id}", handler("edit"))
	mux.HandleFunc("POST "+base+"/sprints/{id}/start", handler("start"))
	mux.HandleFunc("POST "+base+"/sprints/{id}/close", handler("close"))
	mux.HandleFunc("PATCH "+base+"/sprints/{id}/notes", handler("notes"))
}
