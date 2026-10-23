package store

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/mhdolatabadi/farash/server/internal/recurrence"
)

var ErrRecurrenceConflict = errors.New("recurrence state conflict")
var ErrInvalidRecurrence = errors.New("invalid recurrence")

type TaskRecurrence struct {
	Schedule   recurrence.Schedule `json:"schedule"`
	Emitted    int                 `json:"emitted"`
	NextTaskID *string             `json:"next_task_id"`
	AdvancedAt *time.Time          `json:"advanced_at"`
	Skipped    bool                `json:"skipped"`
}

func recurrenceState(ctx context.Context, tx pgx.Tx, owner, id string) (*TaskRecurrence, error) {
	var state TaskRecurrence
	var raw []byte
	err := tx.QueryRow(ctx, `SELECT schedule,emitted,next_task_id,advanced_at,skipped FROM task_recurrences WHERE owner_id=$1 AND task_id=$2 FOR UPDATE`, owner, id).Scan(&raw, &state.Emitted, &state.NextTaskID, &state.AdvancedAt, &state.Skipped)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	err = json.Unmarshal(raw, &state.Schedule)
	return &state, err
}

func (s *Store) TaskRecurrence(ctx context.Context, owner, id string) (*TaskRecurrence, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	var found string
	if err := tx.QueryRow(ctx, `SELECT id FROM tasks WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL FOR UPDATE`, owner, id).Scan(&found); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrTaskNotFound
		}
		return nil, err
	}
	return recurrenceState(ctx, tx, owner, id)
}

// SetTaskRecurrence anchors a rule to the task's current due. Changing a due
// later reschedules that occurrence; it never silently changes this anchor.
func (s *Store) SetTaskRecurrence(ctx context.Context, owner, id string, schedule *recurrence.Schedule) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		task, err := scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL FOR UPDATE`, owner, id))
		if err != nil {
			return err
		}
		state, err := recurrenceState(ctx, tx, owner, id)
		if err != nil {
			return err
		}
		if task.CompletedAt != nil || state != nil && state.AdvancedAt != nil {
			return ErrRecurrenceConflict
		}
		if schedule == nil {
			_, err = tx.Exec(ctx, `DELETE FROM task_recurrences WHERE owner_id=$1 AND task_id=$2`, owner, id)
			return err
		}
		anchor := schedule.Start
		if state != nil {
			// Successors retain the original anchor and emitted count. Editing
			// their rule must not reset the series to today's occurrence.
			anchor = state.Schedule.Start
			if schedule.Start != anchor {
				return ErrInvalidRecurrence
			}
		} else if task.Due != nil && task.Due.Date != anchor {
			return ErrInvalidRecurrence
		}
		if task.ParentID != nil || task.SubtaskCount != 0 || task.Due == nil {
			return ErrInvalidRecurrence
		}
		zone, err := time.LoadLocation(schedule.Timezone)
		if err != nil || schedule.Timezone == "" || schedule.Timezone == "Local" {
			return ErrInvalidRecurrence
		}
		start, err := time.ParseInLocation(dateLayout, schedule.Start, zone)
		if err != nil {
			return ErrInvalidRecurrence
		}
		if task.Due.Datetime == nil && schedule.Time != "" || task.Due.Datetime != nil && (schedule.Time == "" || task.Due.Timezone == nil || *task.Due.Timezone != schedule.Timezone || task.Due.Datetime.In(zone).Format("15:04") != schedule.Time) {
			return ErrInvalidRecurrence
		}
		if _, _, err := recurrence.Next(*schedule, start, 1); err != nil {
			return ErrInvalidRecurrence
		}
		raw, err := json.Marshal(schedule)
		if err != nil {
			return err
		}
		_, err = tx.Exec(ctx, `INSERT INTO task_recurrences(task_id,owner_id,schedule) VALUES($1,$2,$3) ON CONFLICT(task_id) DO UPDATE SET schedule=EXCLUDED.schedule WHERE task_recurrences.owner_id=EXCLUDED.owner_id`, id, owner, raw)
		if err == nil {
			_, err = tx.Exec(ctx, `UPDATE tasks SET updated_at=clock_timestamp() WHERE owner_id=$1 AND id=$2`, owner, id)
		}
		return err
	})
}

// advanceRecurrence runs in the same transaction as ordinary completion.
// Repeated close requests see completed_at already set and do not call this.
func advanceRecurrence(ctx context.Context, tx pgx.Tx, owner, id, kind string) error {
	state, err := recurrenceState(ctx, tx, owner, id)
	if err != nil || state == nil || state.AdvancedAt != nil {
		return err
	}
	task, err := scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2`, owner, id))
	if err != nil {
		return err
	}
	if task.ParentID != nil || task.SubtaskCount != 0 {
		return ErrRecurrenceConflict
	}
	var now time.Time
	if err := tx.QueryRow(ctx, `SELECT clock_timestamp()`).Scan(&now); err != nil {
		return err
	}
	next, exists, err := recurrence.Next(state.Schedule, now, state.Emitted)
	if err != nil {
		return ErrInvalidRecurrence
	}
	var nextID *string
	var version *time.Time
	if exists {
		id := newID()
		nextID = &id
		var zone *string
		if next.Datetime != nil {
			zone = &next.Timezone
		}
		var updated time.Time
		err = tx.QueryRow(ctx, `INSERT INTO tasks(id,owner_id,project_id,section_id,title,description,priority,sort_order,due_date,due_at,due_timezone,deadline,duration_minutes)
			VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::date,$10,$11,$12::date,$13) RETURNING updated_at`, id, owner, task.ProjectID, task.SectionID, task.Title, task.Description, task.Priority, task.SortOrder, next.Date, next.Datetime, zone, task.Deadline, task.DurationMinutes).Scan(&updated)
		if err != nil {
			return err
		}
		version = &updated
		if _, err := tx.Exec(ctx, `INSERT INTO task_labels(owner_id,task_id,label_id) SELECT owner_id,$3,label_id FROM task_labels WHERE owner_id=$1 AND task_id=$2`, owner, task.ID, id); err != nil {
			return err
		}
		raw, _ := json.Marshal(state.Schedule)
		if _, err := tx.Exec(ctx, `INSERT INTO task_recurrences(task_id,owner_id,schedule,emitted) VALUES($1,$2,$3,$4)`, id, owner, raw, state.Emitted+1); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE task_recurrences SET next_task_id=$3,next_version=$4,advanced_at=$5,skipped=$6 WHERE owner_id=$1 AND task_id=$2`, owner, id, nextID, version, now, kind == "skip"); err != nil {
		return err
	}
	due, _ := json.Marshal(task.Due)
	_, err = tx.Exec(ctx, `INSERT INTO recurrence_events(owner_id,task_id,kind,due,successor_id) VALUES($1,$2,$3,$4,$5)`, owner, id, kind, due, nextID)
	return err
}

// Undo never removes a successor that has edits, children, time records or
// another completed occurrence. The caller must resolve that history first.
func undoRecurrence(ctx context.Context, tx pgx.Tx, owner, id string) error {
	state, err := recurrenceState(ctx, tx, owner, id)
	if err != nil || state == nil || state.AdvancedAt == nil {
		return err
	}
	if state.NextTaskID != nil {
		var safe bool
		err := tx.QueryRow(ctx, `SELECT t.completed_at IS NULL AND t.deleted_at IS NULL AND t.updated_at=r.next_version
			AND NOT EXISTS(SELECT 1 FROM tasks c WHERE c.parent_id=t.id)
			AND NOT EXISTS(SELECT 1 FROM time_entries e WHERE e.task_id=t.id)
			AND NOT EXISTS(SELECT 1 FROM scrum_items si WHERE si.task_id=t.id)
			FROM tasks t,task_recurrences r WHERE t.owner_id=$1 AND t.id=$3 AND r.owner_id=$1 AND r.task_id=$2 FOR UPDATE OF t`, owner, id, *state.NextTaskID).Scan(&safe)
		if err != nil || !safe {
			return ErrRecurrenceConflict
		}
		if _, err := tx.Exec(ctx, `DELETE FROM tasks WHERE owner_id=$1 AND id=$2`, owner, *state.NextTaskID); err != nil {
			return err
		}
	}
	if _, err := tx.Exec(ctx, `UPDATE task_recurrences SET next_task_id=NULL,next_version=NULL,advanced_at=NULL,skipped=FALSE WHERE owner_id=$1 AND task_id=$2`, owner, id); err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `INSERT INTO recurrence_events(owner_id,task_id,kind) VALUES($1,$2,'undo')`, owner, id)
	return err
}

func (s *Store) SkipRecurringTask(ctx context.Context, owner, id string) (Task, error) {
	var task Task
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var completed, deleted *time.Time
		err := tx.QueryRow(ctx, `SELECT completed_at,deleted_at FROM tasks WHERE owner_id=$1 AND id=$2 FOR UPDATE`, owner, id).Scan(&completed, &deleted)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrTaskNotFound
		}
		if err != nil {
			return err
		}
		state, err := recurrenceState(ctx, tx, owner, id)
		if err != nil {
			return err
		}
		if state == nil {
			return ErrInvalidRecurrence
		}
		if !state.Skipped {
			if completed != nil || deleted != nil {
				return ErrRecurrenceConflict
			}
			if err := advanceRecurrence(ctx, tx, owner, id, "skip"); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `UPDATE tasks SET deleted_at=clock_timestamp() WHERE owner_id=$1 AND id=$2`, owner, id); err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, `UPDATE time_entries SET ended_at=GREATEST(started_at+interval '1 microsecond',LEAST(now(),COALESCE(planned_end,now()))) WHERE owner_id=$1 AND task_id=$2 AND ended_at IS NULL`, owner, id); err != nil {
				return err
			}
		}
		task, err = scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2`, owner, id))
		return err
	})
	return task, err
}

func (s *Store) UndoRecurringTask(ctx context.Context, owner, id string) (Task, error) {
	var task Task
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		if _, err := scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2 FOR UPDATE`, owner, id)); err != nil {
			return err
		}
		state, err := recurrenceState(ctx, tx, owner, id)
		if err != nil {
			return err
		}
		if state == nil {
			return ErrInvalidRecurrence
		}
		if err := undoRecurrence(ctx, tx, owner, id); err != nil {
			return err
		}
		if state.AdvancedAt != nil {
			if _, err := tx.Exec(ctx, `UPDATE tasks SET completed_at=NULL,deleted_at=CASE WHEN $3 THEN NULL ELSE deleted_at END WHERE owner_id=$1 AND id=$2`, owner, id, state.Skipped); err != nil {
				return err
			}
		}
		task, err = scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2`, owner, id))
		return err
	})
	return task, err
}
