package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type calendarEventsStore interface {
	ListCalendarEvents(context.Context, string, time.Time, time.Time) ([]store.CalendarEvent, error)
	CreateCalendarEvent(context.Context, string, store.CalendarEventInput) (store.CalendarEvent, error)
	UpdateCalendarEvent(context.Context, string, string, store.CalendarEventInput) (store.CalendarEvent, error)
	SetCalendarEventDeleted(context.Context, string, string, bool) (store.CalendarEvent, error)
}

func nativeEventRoutes(mux *http.ServeMux, auth *authHandler, data calendarEventsStore) {
	handler := nativeEventsHandler(auth, data, newRateLimiter(60, time.Minute))
	for _, route := range []string{"GET /api/v1/events", "POST /api/v1/events", "PATCH /api/v1/events/{id}", "DELETE /api/v1/events/{id}", "POST /api/v1/events/{id}/restore"} {
		mux.HandleFunc(route, handler)
	}
}

func nativeEventsHandler(auth *authHandler, data calendarEventsStore, limits *rateLimiter) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		user, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		if r.Method != http.MethodGet && !limits.allow(user.ID) {
			writeError(w, 429, "rate_limited")
			return
		}
		var result any
		var err error
		status := http.StatusOK
		if r.Method == http.MethodGet {
			from, to, e := store.ParseEventWindow(r.URL.Query().Get("from"), r.URL.Query().Get("to"))
			if e != nil {
				writeError(w, 400, "invalid_calendar_event")
				return
			}
			var events []store.CalendarEvent
			events, err = data.ListCalendarEvents(r.Context(), user.ID, from, to)
			result = map[string]any{"events": events}
		} else if r.Method == http.MethodDelete || r.PathValue("id") != "" && r.Method == http.MethodPost {
			var event store.CalendarEvent
			event, err = data.SetCalendarEventDeleted(r.Context(), user.ID, r.PathValue("id"), r.Method == http.MethodDelete)
			result = map[string]any{"event": event}
		} else {
			in, ok := decodeTaskRequest[store.CalendarEventInput](w, r)
			if !ok {
				return
			}
			var event store.CalendarEvent
			if r.Method == http.MethodPatch {
				event, err = data.UpdateCalendarEvent(r.Context(), user.ID, r.PathValue("id"), in)
			} else {
				event, err = data.CreateCalendarEvent(r.Context(), user.ID, in)
				status = http.StatusCreated
			}
			result = map[string]any{"event": event}
		}
		if err != nil {
			switch {
			case errors.Is(err, store.ErrEventNotFound):
				writeError(w, 404, "not_found")
			case errors.Is(err, store.ErrEventInvalid):
				writeError(w, 400, "invalid_calendar_event")
			case errors.Is(err, store.ErrEventConflict):
				writeError(w, 409, "calendar_event_conflict")
			case errors.Is(err, store.ErrEventLimit):
				writeError(w, 409, "calendar_event_limit")
			default:
				writeError(w, 500, "calendar_events_unavailable")
			}
			return
		}
		writeJSON(w, status, result)
	}
}
