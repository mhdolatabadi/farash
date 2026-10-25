package calendar

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"hash/fnv"
	"net/url"
	"sync"
	"time"
)

type Service struct {
	Config   Config
	Provider Provider
	Repo     Repository
	locks    [64]sync.Mutex
}

func random() (string, error) {
	b := make([]byte, 32)
	_, e := rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b), e
}
func Hash(s string) string { v := sha256.Sum256([]byte(s)); return hex.EncodeToString(v[:]) }
func (s *Service) Begin(ctx context.Context, owner, client string, consent bool) (string, error) {
	if client != "web" && client != "android" {
		return "", ErrInvalid
	}
	ticket, e := random()
	if e != nil {
		return "", e
	}
	verifier, e := random()
	if e != nil {
		return "", e
	}
	encrypted, e := s.Config.Seal(owner, "authorization", []byte(verifier))
	if e != nil {
		return "", e
	}
	if e = s.Repo.Begin(ctx, owner, Hash(ticket), encrypted, client, consent); e != nil {
		return "", e
	}
	return s.Config.Origin() + "/api/v1/calendar-authorize/start?ticket=" + url.QueryEscape(ticket), nil
}
func (s *Service) Start(ctx context.Context, ticket string) (authorize, cookie string, err error) {
	if len(ticket) != 43 {
		return "", "", ErrInvalid
	}
	state, e := random()
	if e != nil {
		return "", "", e
	}
	browser, e := random()
	if e != nil {
		return "", "", e
	}
	a, e := s.Repo.Start(ctx, Hash(ticket), Hash(state), Hash(browser))
	if e != nil {
		return "", "", e
	}
	verifier, e := s.Config.Open(a.Owner, "authorization", a.Verifier)
	if e != nil {
		return "", "", e
	}
	challenge := sha256.Sum256(verifier)
	return s.Provider.AuthorizeURL(state, base64.RawURLEncoding.EncodeToString(challenge[:]), a.Consent), browser, nil
}
func (s *Service) Callback(ctx context.Context, state, browser, code, providerError string) (string, error) {
	if len(state) != 43 || len(browser) != 43 {
		return "", ErrInvalid
	}
	a, e := s.Repo.Consume(ctx, Hash(state), Hash(browser))
	if e != nil {
		return "", e
	}
	if providerError != "" || code == "" || len(code) > 4096 {
		return "", ErrInvalid
	}
	verifier, e := s.Config.Open(a.Owner, "authorization", a.Verifier)
	if e != nil {
		return "", e
	}
	t, e := s.Provider.Exchange(ctx, code, string(verifier))
	if e != nil {
		return "", e
	}
	if !hasScopes(t.Scope) || t.Access == "" || t.Refresh == "" {
		return "", ErrReconnect
	}
	id, e := random()
	if e != nil {
		return "", e
	}
	raw, e := json.Marshal(t)
	if e != nil {
		return "", e
	}
	encrypted, e := s.Config.Seal(a.Owner, "connection:"+id, raw)
	if e != nil {
		return "", e
	}
	if _, e = s.Repo.Save(ctx, a.Owner, a.Epoch, id, encrypted); e != nil {
		return "", e
	}
	if a.Client == "android" {
		return s.Config.AndroidReturnURL, nil
	}
	return s.Config.WebReturnURL, nil
}
func (s *Service) lock(id string) func() {
	h := fnv.New32a()
	_, _ = h.Write([]byte(id))
	m := &s.locks[h.Sum32()%uint32(len(s.locks))]
	m.Lock()
	return m.Unlock
}
func (s *Service) token(c Connection) (Token, error) {
	b, e := s.Config.Open(c.Owner, "connection:"+c.ID, c.Credentials)
	if e != nil {
		return Token{}, e
	}
	var t Token
	if json.Unmarshal(b, &t) != nil || t.Refresh == "" || t.Access == "" {
		return Token{}, ErrReconnect
	}
	return t, nil
}
func (s *Service) refresh(ctx context.Context, c Connection, t Token) (Token, error) {
	next, e := s.Provider.Refresh(ctx, t)
	if e != nil {
		if e == ErrReconnect {
			_ = s.Repo.UpdateCredentials(ctx, c, c.Credentials, "reconnect_required")
		}
		return Token{}, e
	}
	if next.Refresh == "" {
		next.Refresh = t.Refresh
	}
	if !hasScopes(next.Scope) {
		return Token{}, ErrReconnect
	}
	b, e := json.Marshal(next)
	if e != nil {
		return Token{}, e
	}
	sealed, e := s.Config.Seal(c.Owner, "connection:"+c.ID, b)
	if e != nil {
		return Token{}, e
	}
	if e = s.Repo.UpdateCredentials(ctx, c, sealed, "connected"); e != nil {
		return Token{}, e
	}
	return next, nil
}
func (s *Service) withToken(ctx context.Context, owner, id string, run func(Connection, Token) error) error {
	unlock := s.lock(id)
	defer unlock()
	c, e := s.Repo.Get(ctx, owner, id)
	if e != nil {
		return e
	}
	if c.Status != "connected" {
		return ErrReconnect
	}
	t, e := s.token(c)
	if e != nil {
		return e
	}
	refreshed := false
	if time.Until(t.Expiry) < time.Minute {
		t, e = s.refresh(ctx, c, t)
		if e != nil {
			return e
		}
		c, e = s.Repo.Get(ctx, owner, id)
		if e != nil {
			return e
		}
		refreshed = true
	}
	e = run(c, t)
	if e == ErrReconnect && !refreshed {
		t, e = s.refresh(ctx, c, t)
		if e != nil {
			return e
		}
		c, e = s.Repo.Get(ctx, owner, id)
		if e != nil {
			return e
		}
		e = run(c, t)
	}
	if e == ErrReconnect {
		_ = s.Repo.UpdateCredentials(ctx, c, c.Credentials, "reconnect_required")
	}
	return e
}

func (s *Service) Calendars(ctx context.Context, owner, id string) ([]Calendar, int64, error) {
	var result []Calendar
	var version int64
	err := s.withToken(ctx, owner, id, func(c Connection, t Token) error {
		all := []Calendar{}
		page := ""
		seen := map[string]bool{}
		for n := 0; n < 20; n++ {
			items, next, e := s.Provider.Calendars(ctx, t, page)
			if e != nil {
				return e
			}
			all = append(all, items...)
			if len(all) > 500 {
				return ErrLimit
			}
			if next == "" {
				result, e = s.Repo.PutCalendars(ctx, c, all)
				version = c.Version
				return e
			}
			if seen[next] || len(next) > 4096 {
				return ErrProvider
			}
			seen[next] = true
			page = next
		}
		return ErrLimit
	})
	return result, version, err
}
func (s *Service) Events(ctx context.Context, owner, id string, from, to time.Time) ([]Event, error) {
	if from.IsZero() || !to.After(from) || to.Sub(from) > 93*24*time.Hour {
		return nil, ErrInvalid
	}
	result := []Event{}
	err := s.withToken(ctx, owner, id, func(c Connection, t Token) error {
		result = []Event{}
		choices, e := s.Repo.Calendars(ctx, owner, id)
		if e != nil {
			return e
		}
		pages := 0
		for _, v := range choices {
			if !v.Selected {
				continue
			}
			page := ""
			seen := map[string]bool{}
			for {
				pages++
				if pages > 20 {
					return ErrLimit
				}
				items, next, e := s.Provider.Events(ctx, t, v.ProviderID, from, to, page)
				if e != nil {
					return e
				}
				for _, item := range items {
					item.ID = Hash(c.ID + "\x00" + v.ID + "\x00" + item.ID)
					item.CalendarID = v.ID
					item.ReadOnly = true
					result = append(result, item)
				}
				if len(result) > 10000 {
					return ErrLimit
				}
				if next == "" {
					break
				}
				if seen[next] || len(next) > 4096 {
					return ErrProvider
				}
				seen[next] = true
				page = next
			}
		}
		current, e := s.Repo.Get(ctx, owner, id)
		if e != nil {
			return e
		}
		if current.Version != c.Version {
			return ErrConflict
		}
		return nil
	})
	if err != nil {
		return nil, err
	}
	return result, nil
}
func (s *Service) Disconnect(ctx context.Context, owner, id string) (bool, error) {
	// Fence and erase locally before the potentially failing remote revoke call.
	c, e := s.Repo.Disconnect(ctx, owner, id)
	if e != nil {
		return false, e
	}
	t, e := s.token(c)
	if e != nil {
		return false, nil
	}
	return s.Provider.Revoke(ctx, t) == nil, nil
}
