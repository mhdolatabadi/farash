package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type commentsStore interface {
	ListComments(context.Context, string, string, string, string) (store.CommentPage, error)
	WriteComment(context.Context, string, string, string, string, string, store.CommentInput) (store.Comment, error)
}

func commentsRoutes(mux *http.ServeMux, auth *authHandler, data commentsStore) {
	limits := newRateLimiter(30, time.Minute)
	handler := func(kind, action string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			user, ok := auth.authenticate(w, r)
			if !ok {
				return
			}
			w.Header().Set("Cache-Control", "no-store")
			var result any
			var err error
			if action == "read" {
				if len(r.URL.Query().Get("after")) > 120 {
					writeError(w, 400, "invalid_comment_input")
					return
				}
				result, err = data.ListComments(r.Context(), user.ID, kind, r.PathValue("target"), r.URL.Query().Get("after"))
			} else {
				if !limits.allow(user.ID) {
					writeError(w, http.StatusTooManyRequests, "rate_limited")
					return
				}
				var in store.CommentInput
				if action != "delete" {
					in, ok = decodeTaskRequest[store.CommentInput](w, r)
					if !ok {
						return
					}
				}
				result, err = data.WriteComment(r.Context(), user.ID, kind, r.PathValue("target"), action, r.PathValue("comment"), in)
			}
			if err != nil {
				switch {
				case errors.Is(err, store.ErrCommentNotFound):
					writeError(w, 404, "not_found")
				case errors.Is(err, store.ErrCommentInvalid):
					writeError(w, 400, "invalid_comment_input")
				case errors.Is(err, store.ErrCommentConflict):
					writeError(w, 409, "comment_state_conflict")
				default:
					writeError(w, 500, "comments_unavailable")
				}
				return
			}
			writeJSON(w, 200, result)
		}
	}
	for _, target := range []struct{ kind, path string }{{"task", "tasks"}, {"project", "projects"}} {
		base := "/api/v1/" + target.path + "/{target}/comments"
		mux.HandleFunc("GET "+base, handler(target.kind, "read"))
		mux.HandleFunc("POST "+base, handler(target.kind, "create"))
		mux.HandleFunc("PATCH "+base+"/{comment}", handler(target.kind, "edit"))
		mux.HandleFunc("DELETE "+base+"/{comment}", handler(target.kind, "delete"))
	}
}
