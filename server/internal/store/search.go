package store

import (
	"context"
	"errors"
	"strconv"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	ErrFilterNotFound = errors.New("filter not found")
	ErrInvalidFilter = errors.New("invalid filter")
)

type SearchPage struct {
	Tasks   []Task `json:"tasks"`
	HasMore bool   `json:"has_more"`
}

func (s *Store) SearchTasks(ctx context.Context, owner string, input SearchOptions) (SearchPage, error) {
	predicate, args, err := compileSearch(input.Query, input.Today)
	if err != nil || input.Offset < 0 || input.Offset > 100000 || input.Limit < 0 || input.Limit > 200 {
		return SearchPage{}, ErrInvalidSearch
	}
	order := "due_date NULLS LAST, due_at NULLS LAST, priority, id"
	switch input.Sort {
	case "", "due":
	case "priority":
		order = "priority, due_date NULLS LAST, id"
	case "title":
		order = normalizedSQL("title") + ", id"
	case "project":
		order = "project_id, sort_order, id"
	default:
		return SearchPage{}, ErrInvalidSearch
	}
	limit := input.Limit
	if limit == 0 {
		limit = 100
	}
	args = append([]any{owner}, args...)
	args = append(args, input.ShowCompleted, limit+1, input.Offset)
	n := len(args)
	query := `SELECT ` + taskColumns + ` FROM tasks WHERE owner_id=$1 AND $2::date IS NOT NULL
		AND deleted_at IS NULL AND ($` + intString(n-2) + ` OR completed_at IS NULL)
		AND project_id IN (SELECT id FROM projects WHERE owner_id=$1 AND kind='project' AND NOT is_archived)
		AND (` + predicate + `) ORDER BY ` + order + ` LIMIT $` + intString(n-1) + ` OFFSET $` + intString(n)
	rows, err := s.pool.Query(ctx, query, args...)
	if err != nil {
		return SearchPage{}, err
	}
	defer rows.Close()
	page := SearchPage{Tasks: []Task{}}
	for rows.Next() {
		task, err := scanTask(rows)
		if err != nil {
			return SearchPage{}, err
		}
		page.Tasks = append(page.Tasks, task)
	}
	if err := rows.Err(); err != nil {
		return SearchPage{}, err
	}
	if len(page.Tasks) > limit {
		page.HasMore = true
		page.Tasks = page.Tasks[:limit]
	}
	return page, nil
}

func intString(value int) string {
	return strconv.Itoa(value)
}

type SavedFilter struct {
	ID         string    `json:"id"`
	Name       string    `json:"name"`
	Query      string    `json:"query"`
	Color      string    `json:"color"`
	IsFavorite bool      `json:"is_favorite"`
	Sort       string    `json:"sort"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

type SavedFilterInput struct {
	Name       string `json:"name"`
	Query      string `json:"query"`
	Color      string `json:"color"`
	IsFavorite bool   `json:"is_favorite"`
	Sort       string `json:"sort"`
}

const savedFilterColumns = "id, name, query, color, is_favorite, sort, created_at, updated_at"

func scanSavedFilter(row projectScanner) (SavedFilter, error) {
	var filter SavedFilter
	err := row.Scan(&filter.ID, &filter.Name, &filter.Query, &filter.Color, &filter.IsFavorite, &filter.Sort, &filter.CreatedAt, &filter.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return SavedFilter{}, ErrFilterNotFound
	}
	return filter, err
}

func validSavedFilter(input *SavedFilterInput) bool {
	input.Name = strings.TrimSpace(input.Name)
	input.Query = strings.TrimSpace(input.Query)
	if input.Color == "" {
		input.Color = "#8B88A0"
	}
	if input.Sort == "" {
		input.Sort = "due"
	}
	if len([]rune(input.Name)) < 1 || len([]rune(input.Name)) > 80 || strings.ContainsAny(input.Name, "\r\n") || !labelColor.MatchString(input.Color) {
		return false
	}
	if input.Sort != "due" && input.Sort != "priority" && input.Sort != "title" && input.Sort != "project" {
		return false
	}
	_, _, err := compileSearch(input.Query, "2000-01-01")
	return err == nil
}

func (s *Store) ListSavedFilters(ctx context.Context, owner string) ([]SavedFilter, error) {
	rows, err := s.pool.Query(ctx, `SELECT `+savedFilterColumns+` FROM saved_filters WHERE owner_id=$1 ORDER BY is_favorite DESC, created_at, id`, owner)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	filters := []SavedFilter{}
	for rows.Next() {
		filter, err := scanSavedFilter(rows)
		if err != nil {
			return nil, err
		}
		filters = append(filters, filter)
	}
	return filters, rows.Err()
}

func (s *Store) SaveFilter(ctx context.Context, owner, id string, input SavedFilterInput) (SavedFilter, error) {
	if !validSavedFilter(&input) {
		return SavedFilter{}, ErrInvalidFilter
	}
	if id == "" {
		return scanSavedFilter(s.pool.QueryRow(ctx, `INSERT INTO saved_filters (id, owner_id, name, query, color, is_favorite, sort)
			VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING `+savedFilterColumns,
			newID(), owner, input.Name, input.Query, input.Color, input.IsFavorite, input.Sort))
	}
	return scanSavedFilter(s.pool.QueryRow(ctx, `UPDATE saved_filters SET name=$3, query=$4, color=$5, is_favorite=$6, sort=$7
		WHERE owner_id=$1 AND id=$2 RETURNING `+savedFilterColumns, owner, id, input.Name, input.Query, input.Color, input.IsFavorite, input.Sort))
}

func (s *Store) DeleteSavedFilter(ctx context.Context, owner, id string) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM saved_filters WHERE owner_id=$1 AND id=$2`, owner, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrFilterNotFound
	}
	return nil
}
