package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type exportStore interface {
	ExportAccount(context.Context, string) ([]byte, error)
}

func exportHandler(auth *authHandler, data exportStore) http.HandlerFunc {
	limits := newRateLimiter(2, time.Minute)
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store, private")
		w.Header().Set("Pragma", "no-cache")
		w.Header().Set("X-Content-Type-Options", "nosniff")
		user, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		// The caller cannot select an owner or query an arbitrary table.
		if r.URL.RawQuery != "" {
			writeError(w, http.StatusBadRequest, "invalid_export_query")
			return
		}
		if !limits.allow(user.ID) {
			w.Header().Set("Retry-After", "60")
			writeError(w, http.StatusTooManyRequests, "rate_limited")
			return
		}
		body, err := data.ExportAccount(r.Context(), user.ID)
		if err != nil {
			switch {
			case errors.Is(err, store.ErrExportTooLarge):
				writeError(w, http.StatusRequestEntityTooLarge, "export_too_large")
			case errors.Is(err, context.DeadlineExceeded):
				writeError(w, http.StatusServiceUnavailable, "export_unavailable")
			default:
				writeError(w, http.StatusInternalServerError, "export_unavailable")
			}
			return
		}
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		w.Header().Set("Content-Disposition", `attachment; filename="farash-export-v1.json"`)
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write(body)
	}
}
