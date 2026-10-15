package store

import (
	"context"
	"errors"
	"regexp"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	ErrLabelNotFound  = errors.New("label not found")
	ErrInvalidLabel   = errors.New("invalid label")
	ErrDuplicateLabel = errors.New("duplicate label")
)

var labelColor = regexp.MustCompile(`^#[0-9A-Fa-f]{6}$`)

type Label struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	Color      string    `json:"color"`
	IsFavorite bool      `json:"is_favorite"`
	SortOrder  int       `json:"sort_order"`
	OpenTasks  int       `json:"open_task_count"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type LabelInput struct {
	Name       string `json:"name"`
	Color      string `json:"color"`
	IsFavorite bool   `json:"is_favorite"`
}

type LabelUpdate struct {
	Name       *string `json:"name"`
	Color      *string `json:"color"`
	IsFavorite *bool   `json:"is_favorite"`
	SortOrder  *int    `json:"sort_order"`
}

const labelColumns = `id, name, color, is_favorite, sort_order,
	(SELECT count(*)::int FROM task_labels tl JOIN tasks t ON t.owner_id=tl.owner_id AND t.id=tl.task_id
	 WHERE tl.owner_id=labels.owner_id AND tl.label_id=labels.id AND t.deleted_at IS NULL AND t.completed_at IS NULL),
	created_at, updated_at`

func scanLabel(row projectScanner) (Label, error) {
	var label Label
	err := row.Scan(&label.ID, &label.Name, &label.Color, &label.IsFavorite, &label.SortOrder, &label.OpenTasks, &label.CreatedAt, &label.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Label{}, ErrLabelNotFound
	}
	if isUniqueViolation(err) {
		return Label{}, ErrDuplicateLabel
	}
	return label, err
}

func isUniqueViolation(err error) bool {
	var pgErr interface{ SQLState() string }
	return errors.As(err, &pgErr) && pgErr.SQLState() == "23505"
}

// cleanLabelName trims the name and allows 1–60 characters on one line; a
// leading @ is dropped so "@تلفن" and "تلفن" are the same label.
func cleanLabelName(name string) (string, bool) {
	name = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(name), "@"))
	length := len([]rune(name))
	return name, length > 0 && length <= 60 && !strings.ContainsAny(name, "\r\n")
}

// ListLabels returns the owner's labels: favourites first, then in order.
func (s *Store) ListLabels(ctx context.Context, owner string) ([]Label, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+labelColumns+` FROM labels WHERE owner_id=$1 ORDER BY is_favorite DESC, sort_order, lower(name), id`, owner)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	labels := []Label{}
	for rows.Next() {
		label, err := scanLabel(rows)
		if err != nil {
			return nil, err
		}
		labels = append(labels, label)
	}
	return labels, rows.Err()
}

func (s *Store) CreateLabel(ctx context.Context, owner string, input LabelInput) (Label, error) {
	name, ok := cleanLabelName(input.Name)
	if !ok {
		return Label{}, ErrInvalidLabel
	}
	color := input.Color
	if color == "" {
		color = "#8B88A0"
	}
	if !labelColor.MatchString(color) {
		return Label{}, ErrInvalidLabel
	}
	return scanLabel(s.pool.QueryRow(ctx, `
		INSERT INTO labels (id, owner_id, name, color, is_favorite, sort_order)
		VALUES ($1, $2, $3, $4, $5, COALESCE((SELECT max(sort_order) + 1 FROM labels WHERE owner_id=$2), 0))
		RETURNING `+labelColumns, newID(), owner, name, color, input.IsFavorite))
}

func (s *Store) UpdateLabel(ctx context.Context, owner, id string, input LabelUpdate) (Label, error) {
	if input.Name != nil {
		name, ok := cleanLabelName(*input.Name)
		if !ok {
			return Label{}, ErrInvalidLabel
		}
		input.Name = &name
	}
	if input.Color != nil && !labelColor.MatchString(*input.Color) {
		return Label{}, ErrInvalidLabel
	}
	return scanLabel(s.pool.QueryRow(ctx, `
		UPDATE labels SET name=COALESCE($3, name), color=COALESCE($4, color), is_favorite=COALESCE($5, is_favorite), sort_order=COALESCE($6, sort_order)
		WHERE owner_id=$1 AND id=$2 RETURNING `+labelColumns, owner, id, input.Name, input.Color, input.IsFavorite, input.SortOrder))
}

// DeleteLabel removes the label from the owner and from every task; the
// tasks themselves stay.
func (s *Store) DeleteLabel(ctx context.Context, owner, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM labels WHERE owner_id=$1 AND id=$2`, owner, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrLabelNotFound
	}
	return nil
}

// ListLabelTasks returns the owner's open tasks with the label, from every
// active project, by project then order.
func (s *Store) ListLabelTasks(ctx context.Context, owner, label string) ([]Task, error) {
	var found string
	err := s.pool.QueryRow(ctx, `SELECT id FROM labels WHERE owner_id=$1 AND id=$2`, owner, label).Scan(&found)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrLabelNotFound
	}
	if err != nil {
		return nil, err
	}
	rows, err := s.pool.Query(ctx, `SELECT `+taskColumns+` FROM tasks
		WHERE owner_id=$1 AND deleted_at IS NULL AND completed_at IS NULL
		AND id IN (SELECT task_id FROM task_labels WHERE owner_id=$1 AND label_id=$2)
		AND project_id IN (SELECT id FROM projects WHERE owner_id=$1 AND kind='project' AND NOT is_archived)
		ORDER BY project_id, sort_order, created_at, id`, owner, label)
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

// setTaskLabels replaces a task's labels; every id must be one of the
// owner's labels, otherwise nothing changes.
func setTaskLabels(ctx context.Context, tx pgx.Tx, owner, task string, ids []string) error {
	unique := []string{}
	seen := map[string]bool{}
	for _, id := range ids {
		if !seen[id] {
			seen[id] = true
			unique = append(unique, id)
		}
	}
	if len(unique) > 50 {
		return ErrInvalidLabel
	}
	var owned int
	if err := tx.QueryRow(ctx, `SELECT count(*)::int FROM labels WHERE owner_id=$1 AND id=ANY($2::text[])`, owner, unique).Scan(&owned); err != nil {
		return err
	}
	if owned != len(unique) {
		return ErrLabelNotFound
	}
	if _, err := tx.Exec(ctx, `DELETE FROM task_labels WHERE owner_id=$1 AND task_id=$2`, owner, task); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `INSERT INTO task_labels (owner_id, task_id, label_id) SELECT $1, $2, unnest($3::text[])`, owner, task, unique)
	return err
}
