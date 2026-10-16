package httpapi

import (
	"context"
	"net/http"
	"time"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type progressStore interface {
	Progress(context.Context, string, time.Time, *time.Location) (store.Progress, error)
	SetProgressGoal(context.Context, string, int) error
	SetWeeklyTaskGoal(context.Context, string, int) error
}

func progressHandler(auth *authHandler, data progressStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		zoneName := r.URL.Query().Get("timezone")
		if zoneName == "" {
			zoneName = "Asia/Tehran"
		}
		zone, err := time.LoadLocation(zoneName)
		if err != nil || zoneName == "Local" {
			writeError(w, http.StatusBadRequest, "invalid_timezone")
			return
		}
		if r.Method == http.MethodPatch && r.URL.Path == "/api/v1/progress/challenge" {
			input, ok := decodeTaskRequest[struct {
				Target int `json:"target"`
			}](w, r)
			if !ok {
				return
			}
			if input.Target < 1 || input.Target > 500 {
				writeError(w, http.StatusBadRequest, "invalid_challenge_target")
				return
			}
			if err := data.SetWeeklyTaskGoal(r.Context(), user.ID, input.Target); err != nil {
				writeError(w, http.StatusInternalServerError, "progress_unavailable")
				return
			}
		} else if r.Method == http.MethodPatch {
			input, ok := decodeTaskRequest[struct {
				Days int `json:"weekly_goal"`
			}](w, r)
			if !ok {
				return
			}
			if input.Days < 1 || input.Days > 7 {
				writeError(w, http.StatusBadRequest, "invalid_weekly_goal")
				return
			}
			if err := data.SetProgressGoal(r.Context(), user.ID, input.Days); err != nil {
				writeError(w, http.StatusInternalServerError, "progress_unavailable")
				return
			}
		}
		progress, err := data.Progress(r.Context(), user.ID, time.Now(), zone)
		if err != nil {
			writeError(w, http.StatusInternalServerError, "progress_unavailable")
			return
		}
		writeJSON(w, http.StatusOK, progress)
	}
}
