package store

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5"
	"time"
)

var ErrTimeNotFound = errors.New("time entry not found")
var ErrTimerRunning = errors.New("another timer is running")
var ErrInvalidTime = errors.New("invalid time interval")

type TimeEntry struct {
	ID         string     `json:"id"`
	TaskID     *string    `json:"task_id"`
	Title      string     `json:"title"`
	Started    time.Time  `json:"started_at"`
	Ended      *time.Time `json:"ended_at"`
	PlannedEnd *time.Time `json:"planned_end"`
	Source     string     `json:"source"`
}
type TimeInput struct {
	TaskID       string     `json:"task_id"`
	Started      time.Time  `json:"started_at"`
	Ended        *time.Time `json:"ended_at"`
	Source       string     `json:"source"`
	RequestKey   string     `json:"request_key"`
	FocusSeconds int        `json:"focus_seconds"`
}
type TaskTime struct {
	TaskID  *string `json:"task_id"`
	Title   string  `json:"title"`
	Project string  `json:"project"`
	Seconds int64   `json:"seconds"`
}
type TimeReport struct {
	Active       *TimeEntry  `json:"active"`
	Entries      []TimeEntry `json:"entries"`
	Tasks        []TaskTime  `json:"tasks"`
	Seconds      int64       `json:"seconds"`
	TodaySeconds int64       `json:"today_seconds"`
	ServerNow    time.Time   `json:"server_now"`
	Truncated    bool        `json:"truncated"`
}

const timeColumns = `id, task_id, task_title, started_at, ended_at, planned_end, source`

func scanTime(row pgx.Row) (TimeEntry, error) {
	var e TimeEntry
	err := row.Scan(&e.ID, &e.TaskID, &e.Title, &e.Started, &e.Ended, &e.PlannedEnd, &e.Source)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrTimeNotFound
	}
	return e, err
}
func validInterval(start time.Time, end *time.Time, now time.Time) bool {
	return !start.IsZero() && end != nil && end.After(start) && !end.After(now.Add(time.Minute)) && end.Sub(start) <= 24*time.Hour
}
func (s *Store) expireTimes(ctx context.Context, owner string) error {
	_, err := s.pool.Exec(ctx, `UPDATE time_entries SET ended_at=planned_end WHERE owner_id=$1 AND ended_at IS NULL AND planned_end<=now()`, owner)
	return err
}
func (s *Store) CreateTime(ctx context.Context, owner string, in TimeInput) (TimeEntry, error) {
	if len(in.RequestKey) < 8 || len(in.RequestKey) > 100 || in.TaskID == "" {
		return TimeEntry{}, ErrInvalidTime
	}
	if in.Source != "timer" && in.Source != "focus" && in.Source != "manual" {
		return TimeEntry{}, ErrInvalidTime
	}
	now := time.Now().UTC()
	if in.Source == "manual" && !validInterval(in.Started, in.Ended, now) {
		return TimeEntry{}, ErrInvalidTime
	}
	if in.Source == "focus" && (in.FocusSeconds < 1 || in.FocusSeconds > 3600) {
		return TimeEntry{}, ErrInvalidTime
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return TimeEntry{}, err
	}
	defer tx.Rollback(ctx)
	// Serialize all starts for this account, including retries from other devices.
	if _, err = tx.Exec(ctx, `SELECT id FROM users WHERE id=$1 FOR UPDATE`, owner); err != nil {
		return TimeEntry{}, err
	}
	if _, err = tx.Exec(ctx, `UPDATE time_entries SET ended_at=planned_end WHERE owner_id=$1 AND ended_at IS NULL AND planned_end<=now()`, owner); err != nil {
		return TimeEntry{}, err
	}
	old, err := scanTime(tx.QueryRow(ctx, `SELECT `+timeColumns+` FROM time_entries WHERE owner_id=$1 AND request_key=$2`, owner, in.RequestKey))
	if err == nil {
		if old.TaskID == nil || *old.TaskID != in.TaskID || old.Source != in.Source {
			return TimeEntry{}, ErrInvalidTime
		}
		if in.Source == "manual" && (!old.Started.Equal(in.Started) || old.Ended == nil || !old.Ended.Equal(*in.Ended)) {
			return TimeEntry{}, ErrInvalidTime
		}
		return old, tx.Commit(ctx)
	}
	if !errors.Is(err, ErrTimeNotFound) {
		return TimeEntry{}, err
	}
	var title string
	if err = tx.QueryRow(ctx, `SELECT title FROM tasks WHERE id=$1 AND owner_id=$2 AND deleted_at IS NULL`, in.TaskID, owner).Scan(&title); errors.Is(err, pgx.ErrNoRows) {
		return TimeEntry{}, ErrTaskNotFound
	} else if err != nil {
		return TimeEntry{}, err
	}
	var planned *time.Time
	if in.Source != "manual" {
		var exists bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM time_entries WHERE owner_id=$1 AND ended_at IS NULL)`, owner).Scan(&exists); err != nil {
			return TimeEntry{}, err
		}
		if exists {
			return TimeEntry{}, ErrTimerRunning
		}
		in.Started = now
		in.Ended = nil
		if in.Source == "focus" {
			at := now.Add(time.Duration(in.FocusSeconds) * time.Second)
			planned = &at
		}
	}
	e, err := scanTime(tx.QueryRow(ctx, `INSERT INTO time_entries(id,owner_id,task_id,task_title,started_at,ended_at,planned_end,source,request_key) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING `+timeColumns, newID(), owner, in.TaskID, title, in.Started, in.Ended, planned, in.Source, in.RequestKey))
	if err != nil {
		return TimeEntry{}, err
	}
	return e, tx.Commit(ctx)
}
func (s *Store) StopTime(ctx context.Context, owner, id string) (TimeEntry, error) {
	// Expected entry ID prevents a stale device from stopping a newer session.
	e, err := scanTime(s.pool.QueryRow(ctx, `UPDATE time_entries SET ended_at=COALESCE(ended_at,GREATEST(started_at+interval '1 microsecond',LEAST(now(),COALESCE(planned_end,now())))) WHERE owner_id=$1 AND id=$2 RETURNING `+timeColumns, owner, id))
	return e, err
}
func (s *Store) EditTime(ctx context.Context, owner, id string, in TimeInput) (TimeEntry, error) {
	if !validInterval(in.Started, in.Ended, time.Now()) {
		return TimeEntry{}, ErrInvalidTime
	}
	// Corrections retain the task and provenance and can also close stale timers.
	return scanTime(s.pool.QueryRow(ctx, `UPDATE time_entries SET started_at=$3,ended_at=$4,planned_end=NULL WHERE owner_id=$1 AND id=$2 RETURNING `+timeColumns, owner, id, in.Started, in.Ended))
}
func (s *Store) DeleteTime(ctx context.Context, owner, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM time_entries WHERE owner_id=$1 AND id=$2`, owner, id)
	if err == nil && tag.RowsAffected() == 0 {
		return ErrTimeNotFound
	}
	return err
}
func (s *Store) TimeReport(ctx context.Context, owner string, from, to time.Time, zone *time.Location, task string) (TimeReport, error) {
	if task != "" {
		var exists bool
		if err := s.pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM tasks WHERE owner_id=$1 AND id=$2)`, owner, task).Scan(&exists); err != nil {
			return TimeReport{}, err
		}
		if !exists {
			return TimeReport{}, ErrTaskNotFound
		}
	}
	now := time.Now().UTC()
	p := TimeReport{Entries: []TimeEntry{}, Tasks: []TaskTime{}, ServerNow: now}
	if err := s.expireTimes(ctx, owner); err != nil {
		return p, err
	}
	a, err := scanTime(s.pool.QueryRow(ctx, `SELECT `+timeColumns+` FROM time_entries WHERE owner_id=$1 AND ended_at IS NULL`, owner))
	if err == nil {
		p.Active = &a
	} else if !errors.Is(err, ErrTimeNotFound) {
		return p, err
	}
	rows, err := s.pool.Query(ctx, `SELECT `+timeColumns+` FROM time_entries WHERE owner_id=$1 AND started_at<$3 AND COALESCE(ended_at,$4)>$2 AND ($5='' OR task_id=$5) ORDER BY started_at DESC,id LIMIT 501`, owner, from, to, now, task)
	if err != nil {
		return p, err
	}
	for rows.Next() {
		e, eerr := scanTime(rows)
		if eerr != nil {
			rows.Close()
			return p, eerr
		}
		if len(p.Entries) < 500 {
			p.Entries = append(p.Entries, e)
		} else {
			p.Truncated = true
		}
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return p, err
	}
	local := now.In(zone)
	today := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, zone)
	groups, err := s.pool.Query(ctx, `SELECT e.task_id,COALESCE(t.title,e.task_title),COALESCE(p.name,''),
 COALESCE(sum(EXTRACT(EPOCH FROM GREATEST(interval '0',LEAST(COALESCE(e.ended_at,$4),$3)-GREATEST(e.started_at,$2)))),0)::bigint,
 COALESCE(sum(EXTRACT(EPOCH FROM GREATEST(interval '0',LEAST(COALESCE(e.ended_at,$4),$3)-GREATEST(e.started_at,$2,$6)))),0)::bigint
 FROM time_entries e LEFT JOIN tasks t ON t.id=e.task_id AND t.owner_id=e.owner_id LEFT JOIN projects p ON p.id=t.project_id AND p.owner_id=e.owner_id
 WHERE e.owner_id=$1 AND e.started_at<$3 AND COALESCE(e.ended_at,$4)>$2 AND ($5='' OR e.task_id=$5)
 GROUP BY e.task_id,COALESCE(t.title,e.task_title),COALESCE(p.name,'') ORDER BY 4 DESC,2`, owner, from, to, now, task, today)
	if err != nil {
		return p, err
	}
	defer groups.Close()
	for groups.Next() {
		var g TaskTime
		var day int64
		if err = groups.Scan(&g.TaskID, &g.Title, &g.Project, &g.Seconds, &day); err != nil {
			return p, err
		}
		p.Tasks = append(p.Tasks, g)
		p.Seconds += g.Seconds
		p.TodaySeconds += day
	}
	return p, groups.Err()
}
