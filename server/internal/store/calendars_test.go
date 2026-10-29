package store

import (
	"context"
	"errors"
	cal "github.com/mhdolatabadi/farash/server/internal/calendar"
	"testing"
)

func TestCalendarBrokerIsolationReplaySelectionAndDisconnectFence(t *testing.T) {
	pool := testPool(t)
	s := New(pool)
	ctx := context.Background()
	a, e := s.CreateUser(ctx, "cal-a@example.com", "hash")
	if e != nil {
		t.Fatal(e)
	}
	b, e := s.CreateUser(ctx, "cal-b@example.com", "hash")
	if e != nil {
		t.Fatal(e)
	}
	if e = s.Begin(ctx, a.ID, "ticket", []byte("encrypted-verifier"), "web", false); e != nil {
		t.Fatal(e)
	}
	attempt, e := s.Start(ctx, "ticket", "state", "browser")
	if e != nil || attempt.Owner != a.ID {
		t.Fatal(attempt, e)
	}
	if _, e = s.Start(ctx, "ticket", "state2", "browser2"); !errors.Is(e, cal.ErrNotFound) {
		t.Fatal("ticket replay", e)
	}
	if _, e = s.Consume(ctx, "state", "wrong-browser"); !errors.Is(e, cal.ErrNotFound) {
		t.Fatal("cookie mismatch", e)
	}
	attempt, e = s.Consume(ctx, "state", "browser")
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.Consume(ctx, "state", "browser"); !errors.Is(e, cal.ErrNotFound) {
		t.Fatal("state replay", e)
	}
	c, e := s.Save(ctx, a.ID, attempt.Epoch, "conn", []byte("encrypted-credentials"))
	if e != nil {
		t.Fatal(e)
	}
	if _, e = s.Get(ctx, b.ID, c.ID); !errors.Is(e, cal.ErrNotFound) {
		t.Fatal("owner leak", e)
	}
	choices, e := s.PutCalendars(ctx, c, []cal.Calendar{{ProviderID: "private-provider-id", Title: "Work", TimeZone: "Asia/Tehran"}})
	if e != nil || len(choices) != 1 {
		t.Fatal(choices, e)
	}
	if choices[0].ID == "private-provider-id" {
		t.Fatal("provider id not opaque")
	}
	if _, e = s.Select(ctx, b.ID, c.ID, c.Version, []string{choices[0].ID}); !errors.Is(e, cal.ErrNotFound) {
		t.Fatal("foreign selection", e)
	}
	version, e := s.Select(ctx, a.ID, c.ID, c.Version, []string{choices[0].ID})
	if e != nil || version != 2 {
		t.Fatal(version, e)
	}
	if _, e = s.Select(ctx, a.ID, c.ID, c.Version, nil); !errors.Is(e, cal.ErrConflict) {
		t.Fatal("stale selection", e)
	}
	if e = s.UpdateCredentials(ctx, c, []byte("late-refresh"), "connected"); !errors.Is(e, cal.ErrConflict) {
		t.Fatal("stale refresh", e)
	}
	if _, e = s.Disconnect(ctx, b.ID, c.ID); !errors.Is(e, cal.ErrNotFound) {
		t.Fatal("foreign disconnect", e)
	}
	if _, e = s.Disconnect(ctx, a.ID, c.ID); e != nil {
		t.Fatal(e)
	}
	if _, e = s.Save(ctx, a.ID, attempt.Epoch, "late-callback", []byte("late")); !errors.Is(e, cal.ErrConflict) {
		t.Fatal("late callback resurrected connection", e)
	}
	var count int
	if e = pool.QueryRow(ctx, `SELECT count(*) FROM connected_calendars`).Scan(&count); e != nil || count != 0 {
		t.Fatal("disconnect retained calendar data", count, e)
	}
	if e = s.Begin(ctx, a.ID, "expired", []byte("v"), "android", false); e != nil {
		t.Fatal(e)
	}
	if _, e = pool.Exec(ctx, `UPDATE calendar_oauth_attempts SET expires_at=now()-interval '1 second'`); e != nil {
		t.Fatal(e)
	}
	if _, e = s.Start(ctx, "expired", "x", "y"); !errors.Is(e, cal.ErrNotFound) {
		t.Fatal("expired start", e)
	}
	for i := 0; i < 3; i++ {
		if e = s.Begin(ctx, a.ID, string(rune('A'+i)), []byte("v"), "web", false); e != nil {
			t.Fatal(e)
		}
	}
	if e = s.Begin(ctx, a.ID, "overflow", []byte("v"), "web", false); !errors.Is(e, cal.ErrLimit) {
		t.Fatal("unbounded attempts", e)
	}
}
