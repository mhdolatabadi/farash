package httpapi

import (
	"context"
	"net/http"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

// syncTaskCreator is deliberately narrower than the full task store.
// CreateTask persists the request key and task in the same transaction.
type syncTaskCreator interface {
	CreateTask(context.Context, string, store.TaskInput) (store.Task, error)
}

// syncTaskCreateHandler is the first push mutation for offline clients.
// Each operation is individually atomic and replay-safe; this is not a batch API.
func syncTaskCreateHandler(auth *authHandler, data syncTaskCreator) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		input, ok := decodeTaskRequest[store.TaskInput](w, r)
		if !ok {
			return
		}
		if input.RequestKey == "" {
			writeError(w, http.StatusBadRequest, "request_key_required")
			return
		}
		task, err := data.CreateTask(r.Context(), user.ID, input)
		if err != nil {
			writeTaskError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, map[string]store.Task{"task": task})
	}
}
