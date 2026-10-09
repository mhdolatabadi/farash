package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	ErrTaskNotFound    = errors.New("task not found")
	ErrInvalidTask     = errors.New("invalid task")
	ErrTaskProject     = errors.New("task project not found")
	ErrInvalidDueRange = errors.New("invalid due range")
	ErrTaskOrder       = errors.New("invalid task order")
)

type Task struct {
	ID          string     `json:"id"`
	ProjectID   string     `json:"project_id"`
	SectionID   *string    `json:"section_id"`
	ParentID    *string    `json:"parent_id"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Priority    int        `json:"priority"`
	SortOrder   int        `json:"sort_order"`
	CompletedAt *time.Time `json:"completed_at"`
	// Due is null for a task without a date.
	Due *Due `json:"due"`
	// Deadline is a YYYY-MM-DD day the task must be done by.
	Deadline        *string   `json:"deadline"`
	DurationMinutes *int      `json:"duration_minutes"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
	// Live direct subtasks, so a list without completed tasks can still show
	// progress such as 2/5.
	SubtaskCount          int `json:"subtask_count"`
	CompletedSubtaskCount int `json:"completed_subtask_count"`
}

type TaskInput struct {
	ProjectID string `json:"project_id"`
	SectionID string `json:"section_id"`
	// ParentID makes the task a subtask; it then lives in the parent's
	// project and section.
	ParentID        string    `json:"parent_id"`
	Title           string    `json:"title"`
	Description     string    `json:"description"`
	Priority        int       `json:"priority"`
	SortOrder       int       `json:"sort_order"`
	Due             *DueInput `json:"due"`
	Deadline        *string   `json:"deadline"`
	DurationMinutes *int      `json:"duration_minutes"`
}

type TaskUpdate struct {
	ProjectID *string `json:"project_id"`
	// SectionID moves the task into a section of its (new) project; an empty
	// string takes it out of its section. Moving to another project without
	// a section_id also takes it out.
	SectionID *string `json:"section_id"`
	// ParentID moves the task (with its subtasks) under another task; an
	// empty string makes it top-level. Moving to another project or section
	// without a parent_id also makes it top-level.
	ParentID    *string `json:"parent_id"`
	Title       *string `json:"title"`
	Description *string `json:"description"`
	Priority    *int    `json:"priority"`
	SortOrder   *int    `json:"sort_order"`
	// Due, Deadline and DurationMinutes are left alone when absent and
	// cleared by null. Clearing the due, or making it all-day, also clears
	// the duration unless one is sent.
	Due             Optional[DueInput] `json:"due"`
	Deadline        Optional[string]   `json:"deadline"`
	DurationMinutes Optional[int]      `json:"duration_minutes"`
}

const taskColumns = `id, project_id, section_id, parent_id, title, description, priority, sort_order, completed_at,
	to_char(due_date, 'YYYY-MM-DD'), due_at, due_timezone, to_char(deadline, 'YYYY-MM-DD'), duration_minutes, created_at, updated_at,
	(SELECT count(*)::int FROM tasks c WHERE c.owner_id=tasks.owner_id AND c.parent_id=tasks.id AND c.deleted_at IS NULL),
	(SELECT count(*)::int FROM tasks c WHERE c.owner_id=tasks.owner_id AND c.parent_id=tasks.id AND c.deleted_at IS NULL AND c.completed_at IS NOT NULL)`

func scanTask(row projectScanner) (Task, error) {
	var task Task
	var dueDate, dueZone *string
	var dueAt *time.Time
	err := row.Scan(&task.ID, &task.ProjectID, &task.SectionID, &task.ParentID, &task.Title, &task.Description, &task.Priority, &task.SortOrder, &task.CompletedAt,
		&dueDate, &dueAt, &dueZone, &task.Deadline, &task.DurationMinutes, &task.CreatedAt, &task.UpdatedAt, &task.SubtaskCount, &task.CompletedSubtaskCount)
	if errors.Is(err, pgx.ErrNoRows) {
		return Task{}, ErrTaskNotFound
	}
	if dueDate != nil {
		task.Due = &Due{Date: *dueDate, Datetime: dueAt, Timezone: dueZone}
	}
	return task, err
}

func validTask(title, description string, priority int) bool {
	return len([]rune(strings.TrimSpace(title))) > 0 && len([]rune(title)) <= 500 && len([]rune(description)) <= 20000 && priority >= 1 && priority <= 4
}

func (s *Store) ListTasks(ctx context.Context, owner, project string, completed bool) ([]Task, error) {
	var projectID string
	err := s.pool.QueryRow(ctx, `SELECT id FROM projects WHERE owner_id=$1 AND id=$2 AND kind='project'`, owner, project).Scan(&projectID)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrTaskProject
	}
	if err != nil {
		return nil, err
	}
	rows, err := s.pool.Query(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND project_id=$2 AND deleted_at IS NULL AND ($3 OR completed_at IS NULL) ORDER BY sort_order, created_at, id`, owner, project, completed)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	tasks := []Task{}
	for rows.Next() {
		task, err := scanTask(rows)
		if err != nil {
			return nil, err
		}
		tasks = append(tasks, task)
	}
	return tasks, rows.Err()
}

// ListDueTasks returns the owner's open tasks due from from to to
// (inclusive, YYYY-MM-DD; an empty from means no lower bound) across their
// active projects, earliest first. The caller picks "today" in its own zone.
func (s *Store) ListDueTasks(ctx context.Context, owner, from, to string) ([]Task, error) {
	if (from != "" && !validDate(from)) || !validDate(to) || (from != "" && from > to) {
		return nil, ErrInvalidDueRange
	}
	if from != "" {
		start, _ := time.Parse(dateLayout, from)
		end, _ := time.Parse(dateLayout, to)
		if end.Sub(start) > 366*24*time.Hour {
			return nil, ErrInvalidDueRange
		}
	}
	rows, err := s.pool.Query(ctx, `SELECT `+taskColumns+` FROM tasks
		WHERE owner_id=$1 AND deleted_at IS NULL AND completed_at IS NULL AND due_date IS NOT NULL
		AND ($2 = '' OR due_date >= $2::date) AND due_date <= $3::date
		AND project_id IN (SELECT id FROM projects WHERE owner_id=$1 AND kind='project' AND NOT is_archived)
		ORDER BY due_date, due_at NULLS LAST, priority, sort_order, created_at, id`, owner, from, to)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	tasks := []Task{}
	for rows.Next() {
		task, err := scanTask(rows)
		if err != nil {
			return nil, err
		}
		tasks = append(tasks, task)
	}
	return tasks, rows.Err()
}

func (s *Store) CreateTask(ctx context.Context, owner string, input TaskInput) (Task, error) {
	input.Title = strings.TrimSpace(input.Title)
	if input.Priority == 0 {
		input.Priority = 4
	}
	if !validTask(input.Title, input.Description, input.Priority) {
		return Task{}, ErrInvalidTask
	}
	var due *Due
	if input.Due != nil {
		normalized, err := normalizeDue(*input.Due)
		if err != nil {
			return Task{}, err
		}
		due = &normalized
	}
	if input.Deadline != nil && !validDate(*input.Deadline) {
		return Task{}, ErrInvalidDeadline
	}
	if !validDuration(input.DurationMinutes, due) {
		return Task{}, ErrInvalidDuration
	}
	dueDate, dueAt, dueZone := dueColumns(due)
	if input.ProjectID == "" && input.SectionID == "" && input.ParentID == "" {
		inbox, err := s.EnsureInboxProject(ctx, owner)
		if err != nil {
			return Task{}, err
		}
		input.ProjectID = inbox.ID
	}
	var task Task
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var section, parent *string
		switch {
		case input.ParentID != "":
			if err := lockTaskTree(ctx, tx, owner); err != nil {
				return err
			}
			p, err := lockParent(ctx, tx, owner, input.ParentID)
			if err != nil {
				return err
			}
			if p.CompletedAt != nil || input.ProjectID != "" && input.ProjectID != p.ProjectID ||
				input.SectionID != "" && (p.SectionID == nil || *p.SectionID != input.SectionID) {
				return ErrInvalidParent
			}
			depth, err := taskDepth(ctx, tx, owner, p.ID)
			if err != nil {
				return err
			}
			if depth >= maxTaskDepth {
				return ErrInvalidParent
			}
			input.ProjectID, section, parent = p.ProjectID, p.SectionID, &p.ID
		case input.SectionID != "":
			project, err := sectionProject(ctx, tx, owner, input.SectionID)
			if err != nil {
				return err
			}
			if input.ProjectID == "" {
				input.ProjectID = project
			} else if input.ProjectID != project {
				return ErrInvalidSection
			}
			section = &input.SectionID
		}
		var err error
		task, err = scanTask(tx.QueryRow(ctx, `INSERT INTO tasks (id, owner_id, project_id, section_id, parent_id, title, description, priority, sort_order, due_date, due_at, due_timezone, deadline, duration_minutes)
			SELECT $1,$2,id,$8,$9,$4,$5,$6,$7,$10::date,$11,$12,$13::date,$14 FROM projects WHERE owner_id=$2 AND id=$3 AND kind='project' AND NOT is_archived RETURNING `+taskColumns,
			newID(), owner, input.ProjectID, input.Title, input.Description, input.Priority, input.SortOrder, section, parent, dueDate, dueAt, dueZone, input.Deadline, input.DurationMinutes))
		if errors.Is(err, ErrTaskNotFound) {
			return ErrTaskProject
		}
		return err
	})
	if err != nil {
		return Task{}, err
	}
	return task, nil
}

func (s *Store) UpdateTask(ctx context.Context, owner, id string, input TaskUpdate) (Task, error) {
	if input.Title != nil {
		trimmed := strings.TrimSpace(*input.Title)
		input.Title = &trimmed
		if trimmed == "" || len([]rune(trimmed)) > 500 {
			return Task{}, ErrInvalidTask
		}
	}
	if input.Description != nil && len([]rune(*input.Description)) > 20000 || input.Priority != nil && (*input.Priority < 1 || *input.Priority > 4) {
		return Task{}, ErrInvalidTask
	}
	var newDue *Due
	if input.Due.Value != nil {
		normalized, err := normalizeDue(*input.Due.Value)
		if err != nil {
			return Task{}, err
		}
		newDue = &normalized
	}
	if input.Deadline.Value != nil && !validDate(*input.Deadline.Value) {
		return Task{}, ErrInvalidDeadline
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Task{}, err
	}
	defer tx.Rollback(ctx)
	if input.ParentID != nil && *input.ParentID != "" {
		if err := lockTaskTree(ctx, tx, owner); err != nil {
			return Task{}, err
		}
	}
	current, err := scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL FOR UPDATE`, owner, id))
	if err != nil {
		return Task{}, err
	}
	project := current.ProjectID
	if input.ProjectID != nil {
		project = *input.ProjectID
	}
	section := current.SectionID
	parent := current.ParentID
	switch {
	case input.ParentID != nil && *input.ParentID != "":
		p, err := lockParent(ctx, tx, owner, *input.ParentID)
		if err != nil {
			return Task{}, err
		}
		if err := checkNewParent(ctx, tx, owner, current, p); err != nil {
			return Task{}, err
		}
		if input.ProjectID != nil && *input.ProjectID != p.ProjectID ||
			input.SectionID != nil && !sameSection(sectionOrNil(*input.SectionID), p.SectionID) {
			return Task{}, ErrInvalidParent
		}
		project, section, parent = p.ProjectID, p.SectionID, &p.ID
	case input.SectionID != nil && *input.SectionID == "":
		section = nil
	case input.SectionID != nil:
		sectionProjectID, err := sectionProject(ctx, tx, owner, *input.SectionID)
		if err != nil {
			return Task{}, err
		}
		if sectionProjectID != project {
			return Task{}, ErrInvalidSection
		}
		section = input.SectionID
	case project != current.ProjectID:
		section = nil
	}
	// Outdenting, or moving a subtask to another project or section on its
	// own, makes it top-level.
	if (input.ParentID == nil || *input.ParentID == "") &&
		(input.ParentID != nil || project != current.ProjectID || !sameSection(section, current.SectionID)) {
		parent = nil
	}
	if input.ProjectID != nil || project != current.ProjectID {
		var found string
		err := tx.QueryRow(ctx, `SELECT id FROM projects WHERE owner_id=$1 AND id=$2 AND kind='project' AND NOT is_archived FOR KEY SHARE`, owner, project).Scan(&found)
		if errors.Is(err, pgx.ErrNoRows) {
			return Task{}, ErrTaskProject
		}
		if err != nil {
			return Task{}, err
		}
	}
	due, deadline, duration := current.Due, current.Deadline, current.DurationMinutes
	if input.Due.Set {
		due = newDue
		// A due that loses its time loses its duration, unless one is sent.
		if due == nil || due.Datetime == nil {
			duration = nil
		}
	}
	if input.Deadline.Set {
		deadline = input.Deadline.Value
	}
	if input.DurationMinutes.Set {
		duration = input.DurationMinutes.Value
	}
	if !validDuration(duration, due) {
		return Task{}, ErrInvalidDuration
	}
	dueDate, dueAt, dueZone := dueColumns(due)
	if err := moveSubtree(ctx, tx, owner, id, project, section); err != nil {
		return Task{}, err
	}
	task, err := scanTask(tx.QueryRow(ctx, `UPDATE tasks SET project_id=$3, title=COALESCE($4,title), description=COALESCE($5,description), priority=COALESCE($6,priority), sort_order=COALESCE($7,sort_order), section_id=$8, parent_id=$9,
		due_date=$10::date, due_at=$11, due_timezone=$12, deadline=$13::date, duration_minutes=$14
		WHERE owner_id=$1 AND id=$2 RETURNING `+taskColumns, owner, id, project, input.Title, input.Description, input.Priority, input.SortOrder, section, parent, dueDate, dueAt, dueZone, deadline, duration))
	if err != nil {
		return Task{}, err
	}
	return task, tx.Commit(ctx)
}

// CompleteTask closes a task with its open subtasks, or reopens it with the
// subtasks that closed together with it and any completed ancestors.
func (s *Store) CompleteTask(ctx context.Context, owner, id string, completed bool) (Task, error) {
	var task Task
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var previous *time.Time
		if err := tx.QueryRow(ctx, `SELECT completed_at FROM tasks WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL FOR UPDATE`, owner, id).Scan(&previous); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrTaskNotFound
			}
			return err
		}
		if completed {
			var at time.Time
			if err := tx.QueryRow(ctx, `UPDATE tasks SET completed_at=COALESCE(completed_at,now()) WHERE owner_id=$1 AND id=$2 RETURNING completed_at`, owner, id).Scan(&at); err != nil {
				return err
			}
			if err := closeSubtree(ctx, tx, owner, id, at); err != nil {
				return err
			}
		} else {
			if previous != nil {
				if _, err := tx.Exec(ctx, `UPDATE tasks SET completed_at=NULL WHERE owner_id=$1 AND id=$2`, owner, id); err != nil {
					return err
				}
				if err := reopenSubtree(ctx, tx, owner, id, *previous); err != nil {
					return err
				}
			}
			if err := reopenAncestors(ctx, tx, owner, id); err != nil {
				return err
			}
		}
		var err error
		task, err = scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2`, owner, id))
		return err
	})
	if err != nil {
		return Task{}, err
	}
	return task, nil
}

// DeleteTask soft-deletes a task and its live subtasks at the same moment.
func (s *Store) DeleteTask(ctx context.Context, owner, id string) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var at time.Time
		err := tx.QueryRow(ctx, `UPDATE tasks SET deleted_at=now() WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL RETURNING deleted_at`, owner, id).Scan(&at)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrTaskNotFound
		}
		if err != nil {
			return err
		}
		return deleteSubtree(ctx, tx, owner, id, at)
	})
}

// RestoreTask brings back a deleted task with the subtasks deleted together
// with it. If its parent is still deleted, or is completed while the task is
// open, the task comes back top-level.
func (s *Store) RestoreTask(ctx context.Context, owner, id string) (Task, error) {
	var task Task
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var at time.Time
		err := tx.QueryRow(ctx, `SELECT deleted_at FROM tasks WHERE owner_id=$1 AND id=$2 AND deleted_at IS NOT NULL FOR UPDATE`, owner, id).Scan(&at)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrTaskNotFound
		}
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE tasks SET deleted_at=NULL WHERE owner_id=$1 AND id=$2`, owner, id); err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `
			UPDATE tasks t SET parent_id=NULL FROM tasks p
			WHERE t.owner_id=$1 AND t.id=$2 AND p.owner_id=$1 AND p.id=t.parent_id
			AND (p.deleted_at IS NOT NULL OR p.completed_at IS NOT NULL AND t.completed_at IS NULL)`, owner, id); err != nil {
			return err
		}
		if err := restoreSubtree(ctx, tx, owner, id, at); err != nil {
			return err
		}
		task, err = scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2`, owner, id))
		return err
	})
	if err != nil {
		return Task{}, err
	}
	return task, nil
}

func sectionOrNil(id string) *string {
	if id == "" {
		return nil
	}
	return &id
}

func sameSection(a, b *string) bool {
	return a == nil && b == nil || a != nil && b != nil && *a == *b
}

// Reorder applies a subset (for example the visible open tasks) atomically.
func (s *Store) ReorderTasks(ctx context.Context, owner, project string, ids []string) error {
	if len(ids) == 0 || len(ids) > 1000 {
		return ErrTaskOrder
	}
	seen := map[string]bool{}
	for _, id := range ids {
		if id == "" || seen[id] {
			return ErrTaskOrder
		}
		seen[id] = true
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	// Lock all affected rows in stable order before writing, including across
	// concurrent reorder requests, to avoid lock-order deadlocks.
	rows, err := tx.Query(ctx, `SELECT id FROM tasks WHERE owner_id=$1 AND project_id=$2 AND id=ANY($3::text[]) AND deleted_at IS NULL ORDER BY id FOR UPDATE`, owner, project, ids)
	if err != nil {
		return err
	}
	count := 0
	for rows.Next() {
		count++
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	if count != len(ids) {
		return ErrTaskNotFound
	}
	for order, id := range ids {
		if _, err := tx.Exec(ctx, `UPDATE tasks SET sort_order=$3 WHERE owner_id=$1 AND id=$2`, owner, id, order); err != nil {
			return err
		}
	}
	return tx.Commit(ctx)
}
