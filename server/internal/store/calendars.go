package store

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	cal "github.com/mhdolatabadi/farash/server/internal/calendar"
)

func calendarErr(err error) error {
	if errors.Is(err, pgx.ErrNoRows) {
		return cal.ErrNotFound
	}
	return err
}
func (s *Store) Begin(ctx context.Context, owner, ticket string, verifier []byte, client string, consent bool) error {
	tx, e := s.pool.Begin(ctx)
	if e != nil {
		return e
	}
	defer tx.Rollback(ctx)
	if _, e = tx.Exec(ctx, `SELECT id FROM users WHERE id=$1 FOR UPDATE`, owner); e != nil {
		return e
	}
	if _, e = tx.Exec(ctx, `INSERT INTO calendar_owner_epochs(owner_id) VALUES($1) ON CONFLICT DO NOTHING`, owner); e != nil {
		return e
	}
	if _, e = tx.Exec(ctx, `DELETE FROM calendar_oauth_attempts WHERE owner_id=$1 AND expires_at<=now()`, owner); e != nil {
		return e
	}
	var count int
	if e = tx.QueryRow(ctx, `SELECT count(*) FROM calendar_oauth_attempts WHERE owner_id=$1`, owner).Scan(&count); e != nil {
		return e
	}
	if count >= 3 {
		return cal.ErrLimit
	}
	_, e = tx.Exec(ctx, `INSERT INTO calendar_oauth_attempts(id,owner_id,epoch,client,ticket_hash,verifier,consent) SELECT $1,$2,epoch,$3,$4,$5,$6 FROM calendar_owner_epochs WHERE owner_id=$2`, newID(), owner, client, ticket, verifier, consent)
	if e != nil {
		return e
	}
	return tx.Commit(ctx)
}
func (s *Store) Start(ctx context.Context, ticket, state, browser string) (cal.Attempt, error) {
	var a cal.Attempt
	e := s.pool.QueryRow(ctx, `UPDATE calendar_oauth_attempts SET ticket_hash=NULL,state_hash=$2,browser_hash=$3 WHERE ticket_hash=$1 AND expires_at>now() RETURNING owner_id,client,epoch,verifier,consent`, ticket, state, browser).Scan(&a.Owner, &a.Client, &a.Epoch, &a.Verifier, &a.Consent)
	return a, calendarErr(e)
}
func (s *Store) Consume(ctx context.Context, state, browser string) (cal.Attempt, error) {
	var a cal.Attempt
	e := s.pool.QueryRow(ctx, `DELETE FROM calendar_oauth_attempts WHERE state_hash=$1 AND browser_hash=$2 AND expires_at>now() RETURNING owner_id,client,epoch,verifier,consent`, state, browser).Scan(&a.Owner, &a.Client, &a.Epoch, &a.Verifier, &a.Consent)
	return a, calendarErr(e)
}
func (s *Store) Save(ctx context.Context, owner string, epoch int64, id string, credentials []byte) (cal.Connection, error) {
	tx, e := s.pool.Begin(ctx)
	if e != nil {
		return cal.Connection{}, e
	}
	defer tx.Rollback(ctx)
	if _, e = tx.Exec(ctx, `SELECT id FROM users WHERE id=$1 FOR UPDATE`, owner); e != nil {
		return cal.Connection{}, e
	}
	var current int64
	if e = tx.QueryRow(ctx, `SELECT epoch FROM calendar_owner_epochs WHERE owner_id=$1`, owner).Scan(&current); e != nil {
		return cal.Connection{}, calendarErr(e)
	}
	if current != epoch {
		return cal.Connection{}, cal.ErrConflict
	}
	if _, e = tx.Exec(ctx, `DELETE FROM calendar_connections WHERE owner_id=$1 AND provider='google'`, owner); e != nil {
		return cal.Connection{}, e
	}
	_, e = tx.Exec(ctx, `INSERT INTO calendar_connections(id,owner_id,provider,status,credentials) VALUES($1,$2,'google','connected',$3)`, id, owner, credentials)
	if e != nil {
		return cal.Connection{}, e
	}
	if e = tx.Commit(ctx); e != nil {
		return cal.Connection{}, e
	}
	return cal.Connection{ID: id, Owner: owner, Provider: "google", Status: "connected", Version: 1, Credentials: credentials}, nil
}
func (s *Store) List(ctx context.Context, owner string) ([]cal.Connection, error) {
	rows, e := s.pool.Query(ctx, `SELECT id,provider,status,version FROM calendar_connections WHERE owner_id=$1 ORDER BY id`, owner)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []cal.Connection{}
	for rows.Next() {
		var c cal.Connection
		if e = rows.Scan(&c.ID, &c.Provider, &c.Status, &c.Version); e != nil {
			return nil, e
		}
		out = append(out, c)
	}
	return out, rows.Err()
}
func (s *Store) Get(ctx context.Context, owner, id string) (cal.Connection, error) {
	var c cal.Connection
	c.Owner = owner
	e := s.pool.QueryRow(ctx, `SELECT id,provider,status,version,credentials FROM calendar_connections WHERE owner_id=$1 AND id=$2`, owner, id).Scan(&c.ID, &c.Provider, &c.Status, &c.Version, &c.Credentials)
	return c, calendarErr(e)
}
func (s *Store) UpdateCredentials(ctx context.Context, c cal.Connection, credentials []byte, status string) error {
	tag, e := s.pool.Exec(ctx, `UPDATE calendar_connections SET credentials=$4,status=$5,version=version+1 WHERE owner_id=$1 AND id=$2 AND version=$3`, c.Owner, c.ID, c.Version, credentials, status)
	if e != nil {
		return e
	}
	if tag.RowsAffected() != 1 {
		return cal.ErrConflict
	}
	return nil
}
func (s *Store) PutCalendars(ctx context.Context, c cal.Connection, choices []cal.Calendar) ([]cal.Calendar, error) {
	tx, e := s.pool.Begin(ctx)
	if e != nil {
		return nil, e
	}
	defer tx.Rollback(ctx)
	var version int64
	if e = tx.QueryRow(ctx, `SELECT version FROM calendar_connections WHERE owner_id=$1 AND id=$2 FOR UPDATE`, c.Owner, c.ID).Scan(&version); e != nil {
		return nil, calendarErr(e)
	}
	if version != c.Version {
		return nil, cal.ErrConflict
	}
	ids := []string{}
	for _, v := range choices {
		ids = append(ids, v.ProviderID)
		_, e = tx.Exec(ctx, `INSERT INTO connected_calendars(id,connection_id,provider_id,title,time_zone) VALUES($1,$2,$3,$4,$5) ON CONFLICT(connection_id,provider_id) DO UPDATE SET title=EXCLUDED.title,time_zone=EXCLUDED.time_zone`, newID(), c.ID, v.ProviderID, v.Title, v.TimeZone)
		if e != nil {
			return nil, e
		}
	}
	if _, e = tx.Exec(ctx, `DELETE FROM connected_calendars WHERE connection_id=$1 AND NOT(provider_id=ANY($2::text[]))`, c.ID, ids); e != nil {
		return nil, e
	}
	if e = tx.Commit(ctx); e != nil {
		return nil, e
	}
	return s.Calendars(ctx, c.Owner, c.ID)
}
func (s *Store) Calendars(ctx context.Context, owner, id string) ([]cal.Calendar, error) {
	if _, e := s.Get(ctx, owner, id); e != nil {
		return nil, e
	}
	rows, e := s.pool.Query(ctx, `SELECT v.id,v.provider_id,v.title,v.time_zone,v.selected FROM connected_calendars v JOIN calendar_connections c ON c.id=v.connection_id WHERE c.owner_id=$1 AND c.id=$2 ORDER BY v.id`, owner, id)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	out := []cal.Calendar{}
	for rows.Next() {
		var v cal.Calendar
		if e = rows.Scan(&v.ID, &v.ProviderID, &v.Title, &v.TimeZone, &v.Selected); e != nil {
			return nil, e
		}
		out = append(out, v)
	}
	return out, rows.Err()
}
func (s *Store) Select(ctx context.Context, owner, id string, version int64, ids []string) (int64, error) {
	if len(ids) > 20 {
		return 0, cal.ErrLimit
	}
	seen := map[string]bool{}
	for _, v := range ids {
		if v == "" || seen[v] {
			return 0, cal.ErrInvalid
		}
		seen[v] = true
	}
	tx, e := s.pool.Begin(ctx)
	if e != nil {
		return 0, e
	}
	defer tx.Rollback(ctx)
	var current int64
	if e = tx.QueryRow(ctx, `SELECT version FROM calendar_connections WHERE owner_id=$1 AND id=$2 FOR UPDATE`, owner, id).Scan(&current); e != nil {
		return 0, calendarErr(e)
	}
	if current != version {
		return 0, cal.ErrConflict
	}
	var count int
	if e = tx.QueryRow(ctx, `SELECT count(*) FROM connected_calendars WHERE connection_id=$1 AND id=ANY($2::text[])`, id, ids).Scan(&count); e != nil {
		return 0, e
	}
	if count != len(ids) {
		return 0, cal.ErrNotFound
	}
	if _, e = tx.Exec(ctx, `UPDATE connected_calendars SET selected=(id=ANY($2::text[])) WHERE connection_id=$1`, id, ids); e != nil {
		return 0, e
	}
	if _, e = tx.Exec(ctx, `UPDATE calendar_connections SET version=version+1 WHERE id=$1`, id); e != nil {
		return 0, e
	}
	return current + 1, tx.Commit(ctx)
}
func (s *Store) Disconnect(ctx context.Context, owner, id string) (cal.Connection, error) {
	tx, e := s.pool.Begin(ctx)
	if e != nil {
		return cal.Connection{}, e
	}
	defer tx.Rollback(ctx)
	if _, e = tx.Exec(ctx, `SELECT id FROM users WHERE id=$1 FOR UPDATE`, owner); e != nil {
		return cal.Connection{}, e
	}
	var c cal.Connection
	c.Owner = owner
	if e = tx.QueryRow(ctx, `DELETE FROM calendar_connections WHERE owner_id=$1 AND id=$2 RETURNING id,provider,status,version,credentials`, owner, id).Scan(&c.ID, &c.Provider, &c.Status, &c.Version, &c.Credentials); e != nil {
		return c, calendarErr(e)
	}
	if _, e = tx.Exec(ctx, `UPDATE calendar_owner_epochs SET epoch=epoch+1 WHERE owner_id=$1`, owner); e != nil {
		return c, e
	}
	if _, e = tx.Exec(ctx, `DELETE FROM calendar_oauth_attempts WHERE owner_id=$1`, owner); e != nil {
		return c, e
	}
	return c, tx.Commit(ctx)
}
