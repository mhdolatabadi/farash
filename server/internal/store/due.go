package store

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"time"
	// Time zones come with the binary, so a slim image needs no tzdata.
	_ "time/tzdata"

	"github.com/jackc/pgx/v5"
)

var (
	ErrInvalidDue      = errors.New("invalid due date")
	ErrInvalidDeadline = errors.New("invalid deadline")
	ErrInvalidDuration = errors.New("invalid duration")
	ErrTaskIDs         = errors.New("invalid task ids")
)

const dateLayout = "2006-01-02"

// Due is when a task is planned: a whole day, or a moment in a time zone.
type Due struct {
	// Date is the local calendar day, YYYY-MM-DD.
	Date string `json:"date"`
	// Datetime is the moment in UTC when a time is set.
	Datetime *time.Time `json:"datetime"`
	// Timezone is the IANA zone the time was chosen in.
	Timezone *string `json:"timezone"`
}

// DueInput sets a due: {"date"} for a whole day, or {"datetime","timezone"}
// for a moment; a date sent with a moment must be that moment's local day.
type DueInput struct {
	Date     string `json:"date"`
	Datetime string `json:"datetime"`
	Timezone string `json:"timezone"`
}

// Optional tells an absent JSON field (leave as is) from null (clear) and a
// value (set).
type Optional[T any] struct {
	Set   bool
	Value *T
}

func (o *Optional[T]) UnmarshalJSON(data []byte) error {
	o.Set = true
	if string(data) == "null" {
		o.Value = nil
		return nil
	}
	// Strict like the request body around it: unknown fields are refused.
	decoder := json.NewDecoder(bytes.NewReader(data))
	decoder.DisallowUnknownFields()
	var value T
	if err := decoder.Decode(&value); err != nil {
		return err
	}
	o.Value = &value
	return nil
}

func validDate(value string) bool {
	date, err := time.Parse(dateLayout, value)
	return err == nil && date.Year() >= 1900 && date.Year() < 2200
}

// normalizeDue checks a due and fills its local date.
func normalizeDue(input DueInput) (Due, error) {
	if input.Datetime == "" && input.Timezone == "" {
		if !validDate(input.Date) {
			return Due{}, ErrInvalidDue
		}
		return Due{Date: input.Date}, nil
	}
	if input.Datetime == "" || input.Timezone == "" || input.Timezone == "Local" {
		return Due{}, ErrInvalidDue
	}
	location, err := time.LoadLocation(input.Timezone)
	if err != nil {
		return Due{}, ErrInvalidDue
	}
	moment, err := time.Parse(time.RFC3339, input.Datetime)
	if err != nil {
		return Due{}, ErrInvalidDue
	}
	date := moment.In(location).Format(dateLayout)
	if !validDate(date) || input.Date != "" && input.Date != date {
		return Due{}, ErrInvalidDue
	}
	moment = moment.UTC()
	zone := input.Timezone
	return Due{Date: date, Datetime: &moment, Timezone: &zone}, nil
}

func validDuration(minutes *int, due *Due) bool {
	return minutes == nil || due != nil && due.Datetime != nil && *minutes >= 1 && *minutes <= 1440
}

// dueColumns are the values the task columns store for a due.
func dueColumns(due *Due) (date *string, at *time.Time, zone *string) {
	if due == nil {
		return nil, nil, nil
	}
	return &due.Date, due.Datetime, due.Timezone
}

// RescheduleTasks gives many tasks the same due (nil: no date) at once,
// keeping every other field. A duration stays only with a timed due.
func (s *Store) RescheduleTasks(ctx context.Context, owner string, ids []string, input *DueInput) ([]Task, error) {
	if len(ids) == 0 || len(ids) > 500 {
		return nil, ErrTaskIDs
	}
	seen := map[string]bool{}
	for _, id := range ids {
		if id == "" || seen[id] {
			return nil, ErrTaskIDs
		}
		seen[id] = true
	}
	var due *Due
	if input != nil {
		normalized, err := normalizeDue(*input)
		if err != nil {
			return nil, err
		}
		due = &normalized
	}
	date, at, zone := dueColumns(due)
	var tasks []Task
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var count int
		if err := tx.QueryRow(ctx, `SELECT count(*) FROM (
			SELECT id FROM tasks WHERE owner_id=$1 AND id=ANY($2::text[]) AND deleted_at IS NULL ORDER BY id FOR UPDATE
		) locked`, owner, ids).Scan(&count); err != nil {
			return err
		}
		if count != len(ids) {
			return ErrTaskNotFound
		}
		if _, err := tx.Exec(ctx, `
			UPDATE tasks SET due_date=$3::date, due_at=$4, due_timezone=$5,
				duration_minutes=CASE WHEN $4::timestamptz IS NULL THEN NULL ELSE duration_minutes END
			WHERE owner_id=$1 AND id=ANY($2::text[])`, owner, ids, date, at, zone); err != nil {
			return err
		}
		rows, err := tx.Query(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=ANY($2::text[]) ORDER BY array_position($2::text[], id)`, owner, ids)
		if err != nil {
			return err
		}
		defer rows.Close()
		tasks = make([]Task, 0, len(ids))
		for rows.Next() {
			task, err := scanTask(rows)
			if err != nil {
				return err
			}
			tasks = append(tasks, task)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return tasks, nil
}
