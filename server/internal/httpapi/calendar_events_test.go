package httpapi

import (
	"context"
	"errors"
	"net/http"
	"testing"
	"time"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

func TestNativeEventsLifecycle(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("event-alice@example.com")
	bob := api.register("event-bob@example.com")
	body := map[string]any{"title": "  جلسه  ", "start_at": "2026-11-27T23:30:00+03:30", "end_at": "2026-11-28T01:00:00+03:30", "time_zone": "Asia/Tehran", "request_key": "event-create-attempt-001"}
	var first, replay struct{ Event store.CalendarEvent }
	for _, route := range []struct{ method, path string }{{"GET", "/api/v1/events"}, {"POST", "/api/v1/events"}, {"PATCH", "/api/v1/events/x"}, {"DELETE", "/api/v1/events/x"}, {"POST", "/api/v1/events/x/restore"}} {
		if c := api.do(route.method, route.path, "", body, nil); c != 401 {
			t.Fatal("auth", route, c)
		}
	}
	if c := api.do("POST", "/api/v1/events", alice, body, &first); c != 201 || first.Event.Title != "جلسه" {
		t.Fatal("create", c, first)
	}
	if c := api.do("POST", "/api/v1/events", alice, body, &replay); c != 201 || replay.Event.ID != first.Event.ID {
		t.Fatal("duplicate retry", c, replay)
	}
	body["title"] = "changed"
	if c := api.do("POST", "/api/v1/events", alice, body, nil); c != 409 {
		t.Fatal("changed replay", c)
	}
	body["title"] = "  جلسه  "
	path := "/api/v1/events/" + first.Event.ID
	for _, method := range []string{"PATCH", "DELETE", "POST"} {
		target := path
		if method == "POST" {
			target += "/restore"
		}
		if c := api.do(method, target, bob, map[string]any{"title": "secret", "version": 1}, nil); c != 404 {
			t.Fatal("ownership", method, c)
		}
	}
	var list struct{ Events []store.CalendarEvent }
	window := "/api/v1/events?from=2026-11-27T21:00:00Z&to=2026-11-28T01:00:00Z"
	if c := api.do("GET", window, alice, nil, &list); c != 200 || len(list.Events) != 1 {
		t.Fatal("overnight overlap", c, list)
	}
	if c := api.do("GET", window, bob, nil, &list); c != 200 || len(list.Events) != 0 {
		t.Fatal("private list", c, list)
	}
	if c := api.do("GET", "/api/v1/events?from=2026-11-27T21:30:00Z&to=2026-11-28T01:00:00Z", alice, nil, &list); c != 200 || len(list.Events) != 0 {
		t.Fatal("exclusive end", c, list)
	}
	if c := api.do("PATCH", path, alice, map[string]any{"title": "جلسه جدید", "version": 1}, &replay); c != 200 || replay.Event.Version != 2 {
		t.Fatal("edit", c, replay)
	}
	if c := api.do("PATCH", path, alice, map[string]any{"title": "stale", "version": 1}, nil); c != 409 {
		t.Fatal("stale edit", c)
	}
	if c := api.do("DELETE", path, alice, nil, nil); c != 200 {
		t.Fatal("delete", c)
	}
	if c := api.do("POST", "/api/v1/events", alice, body, &replay); c != 201 || replay.Event.ID != first.Event.ID {
		t.Fatal("deleted retry", c)
	}
	api.do("GET", window, alice, nil, &list)
	if len(list.Events) != 0 {
		t.Fatal("resurrected deleted event")
	}
	if c := api.do("POST", path+"/restore", alice, nil, &replay); c != 200 {
		t.Fatal("undo", c)
	}
	api.do("GET", window, alice, nil, &list)
	if len(list.Events) != 1 || list.Events[0].Title != "جلسه جدید" {
		t.Fatal("restored", list)
	}
	for _, invalid := range []any{map[string]any{}, map[string]any{"title": "x", "owner_id": "forged"}, map[string]any{"title": "x", "start_at": "2026-11-27T09:00:00", "end_at": "2026-11-27T10:00:00Z", "time_zone": "UTC"}} {
		if c := api.do("POST", "/api/v1/events", alice, invalid, nil); c != 400 {
			t.Fatal("validation", c)
		}
	}
	if c := api.do("GET", "/api/v1/events", alice, nil, nil); c != 400 {
		t.Fatal("missing range", c)
	}
}

type failingEvents struct{ err error }

func (f failingEvents) ListCalendarEvents(context.Context, string, time.Time, time.Time) ([]store.CalendarEvent, error) {
	return nil, f.err
}
func (f failingEvents) CreateCalendarEvent(context.Context, string, store.CalendarEventInput) (store.CalendarEvent, error) {
	return store.CalendarEvent{}, f.err
}
func (f failingEvents) UpdateCalendarEvent(context.Context, string, string, store.CalendarEventInput) (store.CalendarEvent, error) {
	return store.CalendarEvent{}, f.err
}
func (f failingEvents) SetCalendarEventDeleted(context.Context, string, string, bool) (store.CalendarEvent, error) {
	return store.CalendarEvent{}, f.err
}

func TestNativeEventErrorsAndRateLimit(t *testing.T) {
	for _, test := range []struct {
		err     error
		code    int
		machine string
	}{{store.ErrEventNotFound, 404, "not_found"}, {store.ErrEventConflict, 409, "calendar_event_conflict"}, {store.ErrEventInvalid, 400, "invalid_calendar_event"}, {store.ErrEventLimit, 409, "calendar_event_limit"}, {errors.New("private database failure"), 500, "calendar_events_unavailable"}} {
		users := newFakeUsers()
		auth := newAuthHandler(users, []byte("test-secret"), time.Hour)
		mux := http.NewServeMux()
		mux.HandleFunc("POST /api/v1/auth/register", auth.register)
		handler := nativeEventsHandler(auth, failingEvents{test.err}, newRateLimiter(1, time.Hour))
		mux.HandleFunc("POST /api/v1/events", handler)
		api := &dbAPI{t: t, handler: mux}
		token := api.register("errors@example.com")
		var result map[string]any
		if c := api.do("POST", "/api/v1/events", token, map[string]any{}, &result); c != test.code {
			t.Fatalf("error response %v: %d %#v", test.err, c, result)
		}
		if c := api.do("POST", "/api/v1/events", token, map[string]any{}, nil); c != 429 {
			t.Fatal("rate limit", c)
		}
	}
}
