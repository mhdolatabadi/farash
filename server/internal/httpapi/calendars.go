package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	cal "github.com/mhdolatabadi/farash/server/internal/calendar"
)

func calendarError(w http.ResponseWriter, e error) {
	switch {
	case errors.Is(e, cal.ErrNotFound):
		writeError(w, 404, "not_found")
	case errors.Is(e, cal.ErrInvalid):
		writeError(w, 400, "invalid_calendar_input")
	case errors.Is(e, cal.ErrConflict):
		writeError(w, 409, "calendar_state_conflict")
	case errors.Is(e, cal.ErrLimit):
		writeError(w, 409, "calendar_limit_reached")
	case errors.Is(e, cal.ErrReconnect):
		writeError(w, 409, "calendar_reconnect_required")
	default:
		writeError(w, 502, "calendar_provider_unavailable")
	}
}
func calendarRoutes(mux *http.ServeMux, auth *authHandler, s *cal.Service) {
	limits := newRateLimiter(10, time.Minute)
	mux.HandleFunc("GET /api/v1/calendar-connections", func(w http.ResponseWriter, r *http.Request) {
		u, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		connections := []cal.Connection{}
		if s != nil {
			var e error
			connections, e = s.Repo.List(r.Context(), u.ID)
			if e != nil {
				calendarError(w, e)
				return
			}
		}
		writeJSON(w, 200, map[string]any{"configured": s != nil, "connections": connections})
	})
	if s == nil {
		return
	}
	mux.HandleFunc("POST /api/v1/calendar-connections/google/authorize", func(w http.ResponseWriter, r *http.Request) {
		u, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		if !limits.allow(u.ID) {
			writeError(w, 429, "rate_limited")
			return
		}
		in, ok := decodeTaskRequest[struct {
			Client  string `json:"client"`
			Consent bool   `json:"consent"`
		}](w, r)
		if !ok {
			return
		}
		start, e := s.Begin(r.Context(), u.ID, in.Client, in.Consent)
		if e != nil {
			calendarError(w, e)
			return
		}
		writeJSON(w, 200, map[string]string{"start_url": start})
	})
	mux.HandleFunc("GET /api/v1/calendar-authorize/start", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		authorize, cookie, e := s.Start(r.Context(), r.URL.Query().Get("ticket"))
		if e != nil {
			calendarError(w, e)
			return
		}
		http.SetCookie(w, &http.Cookie{Name: "__Host-farash-calendar", Value: cookie, Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteLaxMode, MaxAge: 600})
		http.Redirect(w, r, authorize, http.StatusSeeOther)
	})
	mux.HandleFunc("GET /api/v1/calendar-connections/google/callback", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Header().Set("Referrer-Policy", "no-referrer")
		cookie, e := r.Cookie("__Host-farash-calendar")
		if e != nil {
			writeError(w, 400, "invalid_calendar_input")
			return
		}
		http.SetCookie(w, &http.Cookie{Name: "__Host-farash-calendar", Value: "", Path: "/", Secure: true, HttpOnly: true, SameSite: http.SameSiteLaxMode, MaxAge: -1})
		ctx, cancel := context.WithTimeout(r.Context(), 25*time.Second)
		defer cancel()
		destination, e := s.Callback(ctx, r.URL.Query().Get("state"), cookie.Value, r.URL.Query().Get("code"), r.URL.Query().Get("error"))
		if e != nil {
			calendarError(w, e)
			return
		}
		http.Redirect(w, r, destination, http.StatusSeeOther)
	})
	handler := func(w http.ResponseWriter, r *http.Request) {
		u, ok := auth.authenticate(w, r)
		if !ok {
			return
		}
		w.Header().Set("Cache-Control", "no-store")
		if !limits.allow(u.ID) {
			writeError(w, 429, "rate_limited")
			return
		}
		ctx, cancel := context.WithTimeout(r.Context(), 25*time.Second)
		defer cancel()
		id := r.PathValue("id")
		var result any
		var e error
		switch {
		case r.Method == http.MethodDelete:
			var revoked bool
			revoked, e = s.Disconnect(ctx, u.ID, id)
			result = map[string]bool{"disconnected": true, "revoked": revoked}
		case r.Method == http.MethodPut:
			in, ok := decodeTaskRequest[struct {
				IDs     []string `json:"calendar_ids"`
				Version int64    `json:"version"`
			}](w, r)
			if !ok {
				return
			}
			var version int64
			version, e = s.Repo.Select(ctx, u.ID, id, in.Version, in.IDs)
			result = map[string]int64{"version": version}
		case r.URL.Path == "/api/v1/calendar-connections/"+id+"/calendars":
			var choices []cal.Calendar
			var version int64
			choices, version, e = s.Calendars(ctx, u.ID, id)
			result = map[string]any{"calendars": choices, "version": version}
		default:
			var from, to time.Time
			from, e = time.Parse(time.RFC3339, r.URL.Query().Get("from"))
			if e != nil {
				calendarError(w, cal.ErrInvalid)
				return
			}
			to, e = time.Parse(time.RFC3339, r.URL.Query().Get("to"))
			if e != nil {
				calendarError(w, cal.ErrInvalid)
				return
			}
			var events []cal.Event
			events, e = s.Events(ctx, u.ID, id, from, to)
			result = map[string]any{"events": events, "complete": true}
		}
		if e != nil {
			calendarError(w, e)
			return
		}
		writeJSON(w, 200, result)
	}
	mux.HandleFunc("GET /api/v1/calendar-connections/{id}/calendars", handler)
	mux.HandleFunc("PUT /api/v1/calendar-connections/{id}/selection", handler)
	mux.HandleFunc("GET /api/v1/calendar-connections/{id}/events", handler)
	mux.HandleFunc("DELETE /api/v1/calendar-connections/{id}", handler)
}
