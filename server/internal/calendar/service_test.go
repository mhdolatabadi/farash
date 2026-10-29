package calendar

import (
	"context"
	"encoding/json"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

type testRepository struct {
	Repository
	mu      sync.Mutex
	c       Connection
	choices []Calendar
	gone    bool
}

func (r *testRepository) Get(_ context.Context, owner, id string) (Connection, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.gone || owner != r.c.Owner || id != r.c.ID {
		return Connection{}, ErrNotFound
	}
	return r.c, nil
}
func (r *testRepository) UpdateCredentials(_ context.Context, c Connection, b []byte, status string) error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.gone || c.Version != r.c.Version {
		return ErrConflict
	}
	r.c.Credentials = b
	r.c.Status = status
	r.c.Version++
	return nil
}
func (r *testRepository) Calendars(context.Context, string, string) ([]Calendar, error) {
	return r.choices, nil
}
func (r *testRepository) PutCalendars(_ context.Context, c Connection, choices []Calendar) ([]Calendar, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.gone || c.Version != r.c.Version {
		return nil, ErrConflict
	}
	return choices, nil
}

type testProvider struct {
	Provider
	calendars func(string) ([]Calendar, string, error)
	events    func(string) ([]Event, string, error)
	refresh   func(Token) (Token, error)
}

func (p testProvider) Calendars(_ context.Context, _ Token, page string) ([]Calendar, string, error) {
	return p.calendars(page)
}
func (p testProvider) Events(_ context.Context, _ Token, _ string, _, _ time.Time, page string) ([]Event, string, error) {
	return p.events(page)
}
func (p testProvider) Refresh(_ context.Context, t Token) (Token, error) { return p.refresh(t) }
func fixtureService(t *testing.T, token Token) (*Service, *testRepository) {
	t.Helper()
	c := testConfig()
	raw, _ := json.Marshal(token)
	sealed, e := c.Seal("alice", "connection:c1", raw)
	if e != nil {
		t.Fatal(e)
	}
	repo := &testRepository{c: Connection{ID: "c1", Owner: "alice", Status: "connected", Version: 1, Credentials: sealed}, choices: []Calendar{{ID: "local", ProviderID: "private", Selected: true}}}
	return &Service{Config: c, Repo: repo}, repo
}
func currentToken() Token {
	return Token{Access: "access", Refresh: "refresh", Scope: ListScope + " " + EventsScope, Expiry: time.Now().Add(time.Hour)}
}
func TestWindowCompletenessPaginationAndDisconnectFence(t *testing.T) {
	s, repo := fixtureService(t, currentToken())
	pages := 0
	s.Provider = testProvider{events: func(page string) ([]Event, string, error) {
		pages++
		if page == "" {
			return nil, "page2", nil
		}
		return []Event{{ID: "provider-id", Start: Moment{Date: "2026-10-25"}, End: Moment{Date: "2026-10-26"}}}, "", nil
	}}
	from := time.Date(2026, 10, 25, 0, 0, 0, 0, time.UTC)
	events, e := s.Events(context.Background(), "alice", "c1", from, from.Add(24*time.Hour))
	if e != nil || pages != 2 || len(events) != 1 || events[0].ID == "provider-id" || events[0].CalendarID != "local" || !events[0].ReadOnly {
		t.Fatal(events, pages, e)
	}
	s.Provider = testProvider{events: func(string) ([]Event, string, error) { return []Event{{ID: "partial"}}, "same-page", nil }}
	if events, e = s.Events(context.Background(), "alice", "c1", from, from.Add(time.Hour)); e != ErrProvider || events != nil {
		t.Fatal("partial window published", events, e)
	}
	s.Provider = testProvider{events: func(string) ([]Event, string, error) {
		repo.mu.Lock()
		repo.gone = true
		repo.mu.Unlock()
		return []Event{{ID: "late"}}, "", nil
	}}
	if events, e = s.Events(context.Background(), "alice", "c1", from, from.Add(time.Hour)); e != ErrNotFound || events != nil {
		t.Fatal("late disconnect data", events, e)
	}
}
func TestConcurrentRequestsRefreshOnceAndPreserveRefreshToken(t *testing.T) {
	old := currentToken()
	old.Expiry = time.Now().Add(-time.Hour)
	s, repo := fixtureService(t, old)
	repo.choices = nil
	var refreshes atomic.Int32
	s.Provider = testProvider{refresh: func(t Token) (Token, error) {
		refreshes.Add(1)
		next := currentToken()
		next.Refresh = ""
		return next, nil
	}}
	var wg sync.WaitGroup
	errs := make(chan error, 8)
	for i := 0; i < 8; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, e := s.Events(context.Background(), "alice", "c1", time.Now(), time.Now().Add(time.Hour))
			errs <- e
		}()
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		if e != nil {
			t.Fatal(e)
		}
	}
	if refreshes.Load() != 1 {
		t.Fatal("overlapping refresh", refreshes.Load())
	}
	saved, e := s.token(repo.c)
	if e != nil || saved.Refresh != "refresh" {
		t.Fatal("refresh credential lost", saved, e)
	}
}
func TestRevokedRefreshStopsFurtherProviderCalls(t *testing.T) {
	old := currentToken()
	old.Expiry = time.Now().Add(-time.Hour)
	s, repo := fixtureService(t, old)
	s.Provider = testProvider{refresh: func(Token) (Token, error) { return Token{}, ErrReconnect }}
	from := time.Now()
	if _, e := s.Events(context.Background(), "alice", "c1", from, from.Add(time.Hour)); e != ErrReconnect || repo.c.Status != "reconnect_required" {
		t.Fatal("reconnect state", repo.c, e)
	}
}
