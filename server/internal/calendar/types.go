// Package calendar brokers private, read-only calendar provider connections.
package calendar

import (
	"context"
	"errors"
	"time"
)

var (
	ErrNotFound  = errors.New("calendar object not found")
	ErrInvalid   = errors.New("invalid calendar input")
	ErrConflict  = errors.New("calendar generation changed")
	ErrLimit     = errors.New("calendar limit reached")
	ErrProvider  = errors.New("calendar provider unavailable")
	ErrReconnect = errors.New("calendar reconnect required")
)

const ListScope = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
const EventsScope = "https://www.googleapis.com/auth/calendar.events.readonly"

type Token struct {
	Access  string    `json:"access_token"`
	Refresh string    `json:"refresh_token"`
	Expiry  time.Time `json:"expiry"`
	Scope   string    `json:"scope"`
}
type Attempt struct {
	Owner    string
	Client   string
	Epoch    int64
	Verifier []byte
	Consent  bool
}
type Connection struct {
	ID          string `json:"id"`
	Provider    string `json:"provider"`
	Status      string `json:"status"`
	Version     int64  `json:"version"`
	Owner       string `json:"-"`
	Credentials []byte `json:"-"`
}
type Calendar struct {
	ID         string `json:"id"`
	Title      string `json:"title"`
	TimeZone   string `json:"time_zone"`
	Selected   bool   `json:"selected"`
	ProviderID string `json:"-"`
}
type Moment struct {
	Date     string `json:"date,omitempty"`
	DateTime string `json:"dateTime,omitempty"`
	TimeZone string `json:"timeZone,omitempty"`
}
type Event struct {
	ID         string `json:"id"`
	CalendarID string `json:"calendar_id"`
	Title      string `json:"title"`
	Start      Moment `json:"start"`
	End        Moment `json:"end"`
	Status     string `json:"status"`
	ReadOnly   bool   `json:"read_only"`
}
type Provider interface {
	AuthorizeURL(state, challenge string, consent bool) string
	Exchange(context.Context, string, string) (Token, error)
	Refresh(context.Context, Token) (Token, error)
	Revoke(context.Context, Token) error
	Calendars(context.Context, Token, string) ([]Calendar, string, error)
	Events(context.Context, Token, string, time.Time, time.Time, string) ([]Event, string, error)
}

// Repository implementations must enforce owner isolation and compare versions
// on every write. OAuth attempts are single-use and expire server-side.
type Repository interface {
	Begin(context.Context, string, string, []byte, string, bool) error
	Start(context.Context, string, string, string) (Attempt, error)
	Consume(context.Context, string, string) (Attempt, error)
	Save(context.Context, string, int64, string, []byte) (Connection, error)
	List(context.Context, string) ([]Connection, error)
	Get(context.Context, string, string) (Connection, error)
	UpdateCredentials(context.Context, Connection, []byte, string) error
	PutCalendars(context.Context, Connection, []Calendar) ([]Calendar, error)
	Calendars(context.Context, string, string) ([]Calendar, error)
	Select(context.Context, string, string, int64, []string) (int64, error)
	Disconnect(context.Context, string, string) (Connection, error)
}
