package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	ErrSectionNotFound = errors.New("section not found")
	ErrInvalidSection  = errors.New("invalid section")
)

type Section struct {
	ID          string    `json:"id"`
	ProjectID   string    `json:"project_id"`
	Name        string    `json:"name"`
	SortOrder   int       `json:"sort_order"`
	IsCollapsed bool      `json:"is_collapsed"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

type SectionInput struct {
	ProjectID string `json:"project_id"`
	Name      string `json:"name"`
}

type SectionUpdate struct {
	Name        *string `json:"name"`
	IsCollapsed *bool   `json:"is_collapsed"`
}

const sectionColumns = `id, project_id, name, sort_order, is_collapsed, created_at, updated_at`

func scanSection(row projectScanner) (Section, error) {
	var section Section
	err := row.Scan(&section.ID, &section.ProjectID, &section.Name, &section.SortOrder,
		&section.IsCollapsed, &section.CreatedAt, &section.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Section{}, ErrSectionNotFound
	}
	return section, err
}

// cleanSectionName trims the name and allows 1–120 characters on one line.
func cleanSectionName(name string) (string, bool) {
	name = strings.TrimSpace(name)
	length := len([]rune(name))
	return name, length > 0 && length <= 120 && !strings.ContainsAny(name, "\r\n")
}

// ListSections returns the sections of one of the owner's projects in order.
func (s *Store) ListSections(ctx context.Context, owner, project string) ([]Section, error) {
	var found string
	err := s.pool.QueryRow(ctx, `SELECT id FROM projects WHERE owner_id=$1 AND id=$2 AND kind='project'`, owner, project).Scan(&found)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrTaskProject
	}
	if err != nil {
		return nil, err
	}
	rows, err := s.pool.Query(ctx, `SELECT `+sectionColumns+` FROM sections WHERE owner_id=$1 AND project_id=$2 ORDER BY sort_order, created_at, id`, owner, project)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	sections := []Section{}
	for rows.Next() {
		section, err := scanSection(rows)
		if err != nil {
			return nil, err
		}
		sections = append(sections, section)
	}
	return sections, rows.Err()
}

// CreateSection adds a section after the project's other sections. The
// project must be the owner's, active and not a folder.
func (s *Store) CreateSection(ctx context.Context, owner string, input SectionInput) (Section, error) {
	name, ok := cleanSectionName(input.Name)
	if !ok {
		return Section{}, ErrInvalidSection
	}
	section, err := scanSection(s.pool.QueryRow(ctx, `
		INSERT INTO sections (id, owner_id, project_id, name, sort_order)
		SELECT $1, $2, p.id, $4, COALESCE((SELECT max(sort_order) + 1 FROM sections WHERE owner_id=$2 AND project_id=p.id), 0)
		FROM projects p WHERE p.owner_id=$2 AND p.id=$3 AND p.kind='project' AND NOT p.is_archived
		RETURNING `+sectionColumns, newID(), owner, input.ProjectID, name))
	if errors.Is(err, ErrSectionNotFound) {
		return Section{}, ErrTaskProject
	}
	return section, err
}

// UpdateSection renames or collapses one of the owner's sections.
func (s *Store) UpdateSection(ctx context.Context, owner, id string, input SectionUpdate) (Section, error) {
	if input.Name != nil {
		name, ok := cleanSectionName(*input.Name)
		if !ok {
			return Section{}, ErrInvalidSection
		}
		input.Name = &name
	}
	return scanSection(s.pool.QueryRow(ctx, `
		UPDATE sections SET name=COALESCE($3, name), is_collapsed=COALESCE($4, is_collapsed)
		WHERE owner_id=$1 AND id=$2 RETURNING `+sectionColumns, owner, id, input.Name, input.IsCollapsed))
}

// DeleteSection removes a section. Its tasks stay in the project without a
// section, or are deleted (and so restorable) with deleteTasks.
func (s *Store) DeleteSection(ctx context.Context, owner, id string, deleteTasks bool) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var found string
		err := tx.QueryRow(ctx, `SELECT id FROM sections WHERE owner_id=$1 AND id=$2 FOR UPDATE`, owner, id).Scan(&found)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrSectionNotFound
		}
		if err != nil {
			return err
		}
		if deleteTasks {
			if _, err := tx.Exec(ctx, `UPDATE tasks SET deleted_at=now() WHERE owner_id=$1 AND section_id=$2 AND deleted_at IS NULL`, owner, id); err != nil {
				return err
			}
		}
		_, err = tx.Exec(ctx, `DELETE FROM sections WHERE owner_id=$1 AND id=$2`, owner, id)
		return err
	})
}

// ReorderSections saves the order of a project's sections: ids[0] first.
func (s *Store) ReorderSections(ctx context.Context, owner, project string, ids []string) error {
	if len(ids) == 0 || len(ids) > 500 {
		return ErrInvalidSection
	}
	seen := map[string]bool{}
	for _, id := range ids {
		if id == "" || seen[id] {
			return ErrInvalidSection
		}
		seen[id] = true
	}
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var count int
		if err := tx.QueryRow(ctx, `
			SELECT count(*) FROM (
				SELECT id FROM sections WHERE owner_id=$1 AND project_id=$2 AND id=ANY($3::text[]) ORDER BY id FOR UPDATE
			) locked`, owner, project, ids).Scan(&count); err != nil {
			return err
		}
		if count != len(ids) {
			return ErrSectionNotFound
		}
		_, err := tx.Exec(ctx, `
			UPDATE sections SET sort_order = ordered.position - 1
			FROM unnest($3::text[]) WITH ORDINALITY AS ordered(id, position)
			WHERE sections.owner_id=$1 AND sections.project_id=$2 AND sections.id=ordered.id`, owner, project, ids)
		return err
	})
}

// sectionProject returns the project of one of the owner's sections.
func sectionProject(ctx context.Context, q pgx.Tx, owner, section string) (string, error) {
	var project string
	err := q.QueryRow(ctx, `SELECT project_id FROM sections WHERE owner_id=$1 AND id=$2 FOR KEY SHARE`, owner, section).Scan(&project)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrSectionNotFound
	}
	return project, err
}
