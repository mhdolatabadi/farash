package httpapi

import (
	"context"
	"errors"
	"net/http"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type syncStore interface {
	PullSync(context.Context, string, string, int) (store.SyncPage, error)
}

type syncRequest struct {
	Cursor string `json:"cursor"`
	Limit  int    `json:"limit"`
}

func syncHandler(auth *authHandler, data syncStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		input, ok := decodeTaskRequest[syncRequest](w, r)
		if !ok {
			return
		}
		page, err := data.PullSync(r.Context(), user.ID, input.Cursor, input.Limit)
		if err != nil {
			if errors.Is(err, store.ErrInvalidSync) {
				writeError(w, http.StatusBadRequest, "invalid_sync_request")
			} else {
				writeError(w, http.StatusInternalServerError, "sync_unavailable")
			}
			return
		}
		writeJSON(w, http.StatusOK, page)
	}
}
