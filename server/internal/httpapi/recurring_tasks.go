package httpapi

import (
	"context"
	"net/http"

	"github.com/mhdolatabadi/farash/server/internal/recurrence"
	"github.com/mhdolatabadi/farash/server/internal/store"
)

type recurringTasksStore interface {
	TaskRecurrence(context.Context, string, string) (*store.TaskRecurrence, error)
	SetTaskRecurrence(context.Context, string, string, *recurrence.Schedule) error
	SkipRecurringTask(context.Context, string, string) (store.Task, error)
	UndoRecurringTask(context.Context, string, string) (store.Task, error)
}

func recurringTaskRoutes(mux *http.ServeMux, auth *authHandler, data recurringTasksStore) {
	handler := func(action string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			user, ok := auth.authenticate(w, r)
			if !ok {
				return
			}
			id := r.PathValue("id")
			if action == "skip" || action == "undo" {
				var task store.Task
				var err error
				if action == "skip" {
					task, err = data.SkipRecurringTask(r.Context(), user.ID, id)
				} else {
					task, err = data.UndoRecurringTask(r.Context(), user.ID, id)
				}
				if err != nil {
					writeTaskError(w, err)
					return
				}
				writeJSON(w, http.StatusOK, map[string]store.Task{"task": task})
				return
			}
			if action == "write" {
				input, ok := decodeTaskRequest[struct {
					Schedule *recurrence.Schedule `json:"schedule"`
				}](w, r)
				if !ok {
					return
				}
				if err := data.SetTaskRecurrence(r.Context(), user.ID, id, input.Schedule); err != nil {
					writeTaskError(w, err)
					return
				}
			}
			state, err := data.TaskRecurrence(r.Context(), user.ID, id)
			if err != nil {
				writeTaskError(w, err)
				return
			}
			writeJSON(w, http.StatusOK, map[string]*store.TaskRecurrence{"recurrence": state})
		}
	}
	base := "/api/v1/tasks/{id}/recurrence"
	mux.HandleFunc("GET "+base, handler("read"))
	mux.HandleFunc("PUT "+base, handler("write"))
	mux.HandleFunc("POST "+base+"/skip", handler("skip"))
	mux.HandleFunc("POST "+base+"/undo", handler("undo"))
}
