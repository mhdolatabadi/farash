package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	ErrTaskNotFound = errors.New("task not found")
	ErrInvalidTask  = errors.New("invalid task")
	ErrTaskProject  = errors.New("task project not found")
	ErrTaskOrder    = errors.New("invalid task order")
)

type Task struct {
	ID          string     `json:"id"`
	ProjectID   string     `json:"project_id"`
	Title       string     `json:"title"`
	Description string     `json:"description"`
	Priority    int        `json:"priority"`
	SortOrder   int        `json:"sort_order"`
	CompletedAt *time.Time `json:"completed_at"`
	CreatedAt   time.Time  `json:"created_at"`
	UpdatedAt   time.Time  `json:"updated_at"`
}

type TaskInput struct {
	ProjectID   string `json:"project_id"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Priority    int    `json:"priority"`
	SortOrder   int    `json:"sort_order"`
}

type TaskUpdate struct {
	ProjectID   *string `json:"project_id"`
	Title       *string `json:"title"`
	Description *string `json:"description"`
	Priority    *int    `json:"priority"`
	SortOrder   *int    `json:"sort_order"`
}

const taskColumns = `id, project_id, title, description, priority, sort_order, completed_at, created_at, updated_at`

func scanTask(row projectScanner) (Task, error) {
	var task Task
	err := row.Scan(&task.ID, &task.ProjectID, &task.Title, &task.Description, &task.Priority, &task.SortOrder, &task.CompletedAt, &task.CreatedAt, &task.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Task{}, ErrTaskNotFound
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

func (s *Store) CreateTask(ctx context.Context, owner string, input TaskInput) (Task, error) {
	input.Title = strings.TrimSpace(input.Title)
	if input.Priority == 0 {
		input.Priority = 4
	}
	if !validTask(input.Title, input.Description, input.Priority) {
		return Task{}, ErrInvalidTask
	}
	if input.ProjectID == "" {
		inbox, err := s.EnsureInboxProject(ctx, owner)
		if err != nil {
			return Task{}, err
		}
		input.ProjectID = inbox.ID
	}
	task, err := scanTask(s.pool.QueryRow(ctx, `INSERT INTO tasks (id, owner_id, project_id, title, description, priority, sort_order) SELECT $1,$2,id,$4,$5,$6,$7 FROM projects WHERE owner_id=$2 AND id=$3 AND kind='project' AND NOT is_archived RETURNING `+taskColumns, newID(), owner, input.ProjectID, input.Title, input.Description, input.Priority, input.SortOrder))
	if errors.Is(err, ErrTaskNotFound) {
		return Task{}, ErrTaskProject
	}
	return task, err
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
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return Task{}, err
	}
	defer tx.Rollback(ctx)
	if _, err := scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL FOR UPDATE`, owner, id)); err != nil {
		return Task{}, err
	}
	if input.ProjectID != nil {
		var project string
		err := tx.QueryRow(ctx, `SELECT id FROM projects WHERE owner_id=$1 AND id=$2 AND kind='project' AND NOT is_archived FOR KEY SHARE`, owner, *input.ProjectID).Scan(&project)
		if errors.Is(err, pgx.ErrNoRows) {
			return Task{}, ErrTaskProject
		}
		if err != nil {
			return Task{}, err
		}
	}
	task, err := scanTask(tx.QueryRow(ctx, `UPDATE tasks SET project_id=COALESCE($3,project_id), title=COALESCE($4,title), description=COALESCE($5,description), priority=COALESCE($6,priority), sort_order=COALESCE($7,sort_order) WHERE owner_id=$1 AND id=$2 RETURNING `+taskColumns, owner, id, input.ProjectID, input.Title, input.Description, input.Priority, input.SortOrder))
	if err != nil {
		return Task{}, err
	}
	return task, tx.Commit(ctx)
}

func (s *Store) CompleteTask(ctx context.Context, owner, id string, completed bool) (Task, error) {
	return scanTask(s.pool.QueryRow(ctx, `UPDATE tasks SET completed_at=CASE WHEN $3 THEN COALESCE(completed_at,now()) ELSE NULL END WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL RETURNING `+taskColumns, owner, id, completed))
}

func (s *Store) DeleteTask(ctx context.Context, owner, id string) error {
	tag, err := s.pool.Exec(ctx, `UPDATE tasks SET deleted_at=now() WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL`, owner, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrTaskNotFound
	}
	return nil
}

func (s *Store) RestoreTask(ctx context.Context, owner, id string) (Task, error) {
	return scanTask(s.pool.QueryRow(ctx, `UPDATE tasks SET deleted_at=NULL WHERE owner_id=$1 AND id=$2 AND deleted_at IS NOT NULL RETURNING `+taskColumns, owner, id))
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
