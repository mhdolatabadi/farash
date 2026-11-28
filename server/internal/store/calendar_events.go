package store

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
)

var (
	ErrEventNotFound = errors.New("calendar event not found")
	ErrEventInvalid  = errors.New("invalid calendar event")
	ErrEventConflict = errors.New("calendar event changed")
	ErrEventLimit    = errors.New("calendar event limit reached")
)

// CalendarEvent is an owned appointment, independent of tasks and providers.
type CalendarEvent struct {
	ID       string    `json:"id"`
	Title    string    `json:"title"`
	StartAt  time.Time `json:"start_at"`
	EndAt    time.Time `json:"end_at"`
	TimeZone string    `json:"time_zone"`
	Version  int64     `json:"version"`
}

type CalendarEventInput struct {
	Title      *string `json:"title"`
	StartAt    *string `json:"start_at"`
	EndAt      *string `json:"end_at"`
	TimeZone   *string `json:"time_zone"`
	Version    *int64  `json:"version,omitempty"`
	RequestKey string  `json:"request_key,omitempty"`
}

func (in CalendarEventInput) apply(e *CalendarEvent) error {
	if in.Title != nil {
		e.Title = strings.TrimSpace(*in.Title)
	}
	for _, field := range []struct {
		input *string
		value *time.Time
	}{{in.StartAt, &e.StartAt}, {in.EndAt, &e.EndAt}} {
		if field.input != nil {
			parsed, err := time.Parse(time.RFC3339, *field.input)
			if err != nil {
				return ErrEventInvalid
			}
			*field.value = parsed.UTC()
		}
	}
	if in.TimeZone != nil {
		e.TimeZone = *in.TimeZone
	}
	_, zoneErr := time.LoadLocation(e.TimeZone)
	if e.Title == "" || utf8.RuneCountInString(e.Title) > 200 || e.StartAt.Year() < 2000 || e.EndAt.Year() > 2200 || !e.EndAt.After(e.StartAt) || e.EndAt.Sub(e.StartAt) > 7*24*time.Hour || e.TimeZone == "" || e.TimeZone == "Local" || zoneErr != nil {
		return ErrEventInvalid
	}
	return nil
}

// Event windows use instants and exclusive end bounds, including overnight
// appointments which start before the window and finish inside it.
func ParseEventWindow(from, to string) (time.Time, time.Time, error) {
	a, e1 := time.Parse(time.RFC3339, from)
	b, e2 := time.Parse(time.RFC3339, to)
	if e1 != nil || e2 != nil || !b.After(a) || b.Sub(a) > 93*24*time.Hour {
		return time.Time{}, time.Time{}, ErrEventInvalid
	}
	return a.UTC(), b.UTC(), nil
}

const eventColumns = `id,title,start_at,end_at,time_zone,version`

func scanEvent(row pgx.Row) (CalendarEvent, error) {
	var e CalendarEvent
	err := row.Scan(&e.ID, &e.Title, &e.StartAt, &e.EndAt, &e.TimeZone, &e.Version)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrEventNotFound
	}
	return e, err
}

func (s *Store) ListCalendarEvents(ctx context.Context, owner string, from, to time.Time) ([]CalendarEvent, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+eventColumns+` FROM native_calendar_events WHERE owner_id=$1 AND deleted_at IS NULL AND start_at<$3 AND end_at>$2 ORDER BY start_at,id LIMIT 1001`, owner, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	events := []CalendarEvent{}
	for rows.Next() {
		e, err := scanEvent(rows)
		if err != nil {
			return nil, err
		}
		events = append(events, e)
	}
	if len(events) > 1000 {
		return nil, ErrEventLimit
	}
	return events, rows.Err()
}

func (s *Store) CreateCalendarEvent(ctx context.Context, owner string, in CalendarEventInput) (CalendarEvent, error) {
	e := CalendarEvent{Version: 1}
	if in.Version != nil || (in.RequestKey != "" && !habitRequestKey.MatchString(in.RequestKey)) {
		return e, ErrEventInvalid
	}
	if err := in.apply(&e); err != nil {
		return e, err
	}
	payload, _ := json.Marshal(e)
	hash := sha256.Sum256(payload)
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return e, err
	}
	defer tx.Rollback(ctx)
	if _, err = tx.Exec(ctx, `SELECT id FROM users WHERE id=$1 FOR UPDATE`, owner); err != nil {
		return e, err
	}
	if in.RequestKey != "" {
		var previousHash, response []byte
		err = tx.QueryRow(ctx, `SELECT payload_hash,response FROM calendar_event_create_requests WHERE owner_id=$1 AND request_key=$2`, owner, in.RequestKey).Scan(&previousHash, &response)
		if err == nil {
			if string(previousHash) != string(hash[:]) {
				return e, ErrEventConflict
			}
			if err = json.Unmarshal(response, &e); err != nil {
				return e, err
			}
			return e, tx.Commit(ctx)
		}
		if !errors.Is(err, pgx.ErrNoRows) {
			return e, err
		}
	}
	var count int
	if err = tx.QueryRow(ctx, `SELECT count(*) FROM native_calendar_events WHERE owner_id=$1`, owner).Scan(&count); err != nil {
		return e, err
	}
	if count >= 10000 {
		return e, ErrEventLimit
	}
	e.ID = newID()
	if _, err = tx.Exec(ctx, `INSERT INTO native_calendar_events(id,owner_id,title,start_at,end_at,time_zone) VALUES($1,$2,$3,$4,$5,$6)`, e.ID, owner, e.Title, e.StartAt, e.EndAt, e.TimeZone); err != nil {
		return e, err
	}
	if in.RequestKey != "" {
		response, _ := json.Marshal(e)
		if _, err = tx.Exec(ctx, `INSERT INTO calendar_event_create_requests(owner_id,request_key,payload_hash,response) VALUES($1,$2,$3,$4)`, owner, in.RequestKey, hash[:], response); err != nil {
			return e, err
		}
	}
	return e, tx.Commit(ctx)
}

func (s *Store) UpdateCalendarEvent(ctx context.Context, owner, id string, in CalendarEventInput) (CalendarEvent, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return CalendarEvent{}, err
	}
	defer tx.Rollback(ctx)
	e, err := scanEvent(tx.QueryRow(ctx, `SELECT `+eventColumns+` FROM native_calendar_events WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL FOR UPDATE`, owner, id))
	if err != nil {
		return e, err
	}
	if in.Version == nil || *in.Version != e.Version {
		return e, ErrEventConflict
	}
	if in.RequestKey != "" {
		return e, ErrEventInvalid
	}
	if err = in.apply(&e); err != nil {
		return e, err
	}
	e.Version++
	_, err = tx.Exec(ctx, `UPDATE native_calendar_events SET title=$3,start_at=$4,end_at=$5,time_zone=$6,version=$7 WHERE owner_id=$1 AND id=$2`, owner, id, e.Title, e.StartAt, e.EndAt, e.TimeZone, e.Version)
	if err != nil {
		return e, err
	}
	return e, tx.Commit(ctx)
}

// Soft deletion permits the client's undo action without losing the event.
func (s *Store) SetCalendarEventDeleted(ctx context.Context, owner, id string, deleted bool) (CalendarEvent, error) {
	return scanEvent(s.pool.QueryRow(ctx, `UPDATE native_calendar_events SET deleted_at=CASE WHEN $3 THEN COALESCE(deleted_at,now()) ELSE NULL END,version=version+1 WHERE owner_id=$1 AND id=$2 RETURNING `+eventColumns, owner, id, deleted))
}
