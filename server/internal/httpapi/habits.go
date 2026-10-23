package httpapi

import (
	"context"
	"errors"
	"net/http"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type habitsStore interface {
	ListHabits(context.Context, string) ([]store.Habit, error)
	CreateHabit(context.Context, string, store.HabitInput) (store.Habit, error)
	UpdateHabit(context.Context, string, string, store.HabitInput) (store.Habit, error)
	DeleteHabit(context.Context, string, string) error
	ReorderHabits(context.Context, string, []string) error
	SetHabitEntry(context.Context, string, string, string, store.HabitEntryInput) (store.HabitEntry, error)
	ClearHabitEntry(context.Context, string, string, string) error
}

func habitRoutes(mux *http.ServeMux, auth *authHandler, data habitsStore) {
	handler := habitsHandler(auth, data)
	mux.HandleFunc("GET /api/v1/habits", handler)
	mux.HandleFunc("POST /api/v1/habits", handler)
	mux.HandleFunc("POST /api/v1/habits/reorder", handler)
	mux.HandleFunc("PATCH /api/v1/habits/{id}", handler)
	mux.HandleFunc("DELETE /api/v1/habits/{id}", handler)
	mux.HandleFunc("PUT /api/v1/habits/{id}/entries/{day}", handler)
	mux.HandleFunc("DELETE /api/v1/habits/{id}/entries/{day}", handler)
}

func habitsHandler(auth *authHandler, data habitsStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		var result any
		var err error
		id, day := r.PathValue("id"), r.PathValue("day")
		switch {
		case r.Method == http.MethodGet:
			var habits []store.Habit
			habits, err = data.ListHabits(r.Context(), user.ID)
			result = map[string][]store.Habit{"habits": habits}
		case r.Method == http.MethodDelete && day != "":
			err = data.ClearHabitEntry(r.Context(), user.ID, id, day)
			result = map[string]bool{"deleted": true}
		case r.Method == http.MethodDelete:
			err = data.DeleteHabit(r.Context(), user.ID, id)
			result = map[string]bool{"deleted": true}
		case r.Method == http.MethodPut:
			in, ok := decodeTaskRequest[store.HabitEntryInput](w, r)
			if !ok {
				return
			}
			var entry store.HabitEntry
			entry, err = data.SetHabitEntry(r.Context(), user.ID, id, day, in)
			result = map[string]store.HabitEntry{"entry": entry}
		case r.URL.Path == "/api/v1/habits/reorder":
			in, ok := decodeTaskRequest[struct {
				IDs []string `json:"habit_ids"`
			}](w, r)
			if !ok {
				return
			}
			err = data.ReorderHabits(r.Context(), user.ID, in.IDs)
			result = map[string]bool{"reordered": true}
		default:
			in, ok := decodeTaskRequest[store.HabitInput](w, r)
			if !ok {
				return
			}
			var habit store.Habit
			if r.Method == http.MethodPatch {
				habit, err = data.UpdateHabit(r.Context(), user.ID, id, in)
			} else {
				habit, err = data.CreateHabit(r.Context(), user.ID, in)
			}
			result = map[string]store.Habit{"habit": habit}
		}
		if err != nil {
			switch {
			case errors.Is(err, store.ErrHabitNotFound):
				writeError(w, http.StatusNotFound, "not_found")
			case errors.Is(err, store.ErrInvalidHabit):
				writeError(w, http.StatusBadRequest, "invalid_habit")
			case errors.Is(err, store.ErrInvalidEntry):
				writeError(w, http.StatusBadRequest, "invalid_habit_entry")
			case errors.Is(err, store.ErrHabitRequestConflict):
				writeError(w, http.StatusConflict, "habit_request_conflict")
			case errors.Is(err, store.ErrHabitLimit):
				writeError(w, http.StatusConflict, "habit_limit_reached")
			default:
				writeError(w, http.StatusInternalServerError, "habits_unavailable")
			}
			return
		}
		status := http.StatusOK
		if r.Method == http.MethodPost && id == "" && r.URL.Path == "/api/v1/habits" {
			status = http.StatusCreated
		}
		writeJSON(w, status, result)
	}
}
