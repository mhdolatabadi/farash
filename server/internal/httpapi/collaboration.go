package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type collaborationStore interface {
	ProjectCollaboration(context.Context, string, string) (store.ProjectCollaboration, error)
	CollaborationInvitations(context.Context, string) ([]store.ProjectInvitation, error)
	CollaborationWrite(context.Context, string, string, string, string, store.CollaborationCommand) error
}

func collaborationRoutes(mux *http.ServeMux, auth *authHandler, data collaborationStore) {
	limits := newRateLimiter(20, time.Minute)
	handler := func(action string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			user, ok := auth.authenticate(w, r)
			if !ok {
				return
			}
			var result any
			var err error
			switch action {
			case "read":
				result, err = data.ProjectCollaboration(r.Context(), user.ID, r.PathValue("project"))
			case "invitations":
				result, err = data.CollaborationInvitations(r.Context(), user.ID)
			default:
				var in store.CollaborationCommand
				if action == "invite" || action == "role" {
					in, ok = decodeTaskRequest[store.CollaborationCommand](w, r)
					if !ok {
						return
					}
				}
				if !limits.allow(user.ID) {
					writeError(w, http.StatusTooManyRequests, "rate_limited")
					return
				}
				err = data.CollaborationWrite(r.Context(), user.ID, r.PathValue("project"), action, r.PathValue("id"), in)
			}
			if err != nil {
				switch {
				case errors.Is(err, store.ErrCollaborationNotFound):
					writeError(w, http.StatusNotFound, "not_found")
				case errors.Is(err, store.ErrCollaborationInvalid):
					writeError(w, http.StatusBadRequest, "invalid_collaboration_input")
				case errors.Is(err, store.ErrCollaborationConflict):
					writeError(w, http.StatusConflict, "collaboration_state_conflict")
				default:
					writeError(w, http.StatusInternalServerError, "collaboration_unavailable")
				}
				return
			}
			if action == "read" || action == "invitations" {
				writeJSON(w, http.StatusOK, result)
			} else {
				w.WriteHeader(http.StatusNoContent)
			}
		}
	}
	base := "/api/v1/projects/{project}/collaboration"
	mux.HandleFunc("GET "+base, handler("read"))
	mux.HandleFunc("POST "+base+"/invitations", handler("invite"))
	mux.HandleFunc("DELETE "+base+"/invitations/{id}", handler("revoke"))
	mux.HandleFunc("POST "+base+"/invitations/{id}/accept", handler("accept"))
	mux.HandleFunc("POST "+base+"/invitations/{id}/decline", handler("decline"))
	mux.HandleFunc("PATCH "+base+"/members/{id}", handler("role"))
	mux.HandleFunc("DELETE "+base+"/members/{id}", handler("remove"))
	mux.HandleFunc("POST "+base+"/leave", handler("leave"))
	mux.HandleFunc("GET /api/v1/collaboration/invitations", handler("invitations"))
}
