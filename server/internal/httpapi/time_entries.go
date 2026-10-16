package httpapi

import (
	"context"
	"errors"
	"github.com/mhdolatabadi/farash/server/internal/store"
	"net/http"
	"time"
)

type timeStore interface {
	CreateTime(context.Context, string, store.TimeInput) (store.TimeEntry, error)
	StopTime(context.Context, string, string) (store.TimeEntry, error)
	EditTime(context.Context, string, string, store.TimeInput) (store.TimeEntry, error)
	DeleteTime(context.Context, string, string) error
	TimeReport(context.Context, string, time.Time, time.Time, *time.Location, string) (store.TimeReport, error)
}

func timeHandler(auth *authHandler, data timeStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		var result any
		var err error
		id := r.PathValue("id")
		switch {
		case r.Method == http.MethodGet:
			name := r.URL.Query().Get("timezone")
			if name == "" {
				name = "Asia/Tehran"
			}
			zone, zerr := time.LoadLocation(name)
			if zerr != nil || name == "Local" {
				writeError(w, 400, "invalid_timezone")
				return
			}
			from, to := store.ProgressWeek(time.Now(), zone)
			if r.URL.Query().Get("taskId") != "" {
				from = time.Unix(0, 0)
				to = time.Now()
			}
			if r.URL.Query().Has("from") || r.URL.Query().Has("to") {
				from, err = time.Parse(time.RFC3339, r.URL.Query().Get("from"))
				if err == nil {
					to, err = time.Parse(time.RFC3339, r.URL.Query().Get("to"))
				}
				if err != nil || !to.After(from) || to.Sub(from) > 32*24*time.Hour {
					writeError(w, 400, "invalid_time_range")
					return
				}
			}
			result, err = data.TimeReport(r.Context(), user.ID, from, to, zone, r.URL.Query().Get("taskId"))
		case r.Method == http.MethodDelete:
			err = data.DeleteTime(r.Context(), user.ID, id)
			result = map[string]bool{"deleted": true}
		case r.Method == http.MethodPost && id != "":
			result, err = data.StopTime(r.Context(), user.ID, id)
		default:
			in, ok := decodeTaskRequest[store.TimeInput](w, r)
			if !ok {
				return
			}
			if r.Method == http.MethodPatch {
				result, err = data.EditTime(r.Context(), user.ID, id, in)
			} else {
				result, err = data.CreateTime(r.Context(), user.ID, in)
			}
		}
		if err != nil {
			switch {
			case errors.Is(err, store.ErrTimeNotFound), errors.Is(err, store.ErrTaskNotFound):
				writeError(w, 404, "not_found")
			case errors.Is(err, store.ErrInvalidTime):
				writeError(w, 400, "invalid_time_entry")
			case errors.Is(err, store.ErrTimerRunning):
				writeError(w, 409, "timer_already_running")
			default:
				writeError(w, 500, "time_unavailable")
			}
			return
		}
		writeJSON(w, 200, result)
	}
}
