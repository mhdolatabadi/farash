package store

import (
	"context"
	"errors"
	"strings"
)

var (
	ErrProjectNotFound = errors.New("project not found")
	ErrInboxProject    = errors.New("inbox project cannot be changed this way")
)

type Project struct {
	ID         string  `json:"id"`
	OwnerID    string  `json:"owner_id"`
	ParentID   *string `json:"parent_id,omitempty"`
	Name       string  `json:"name"`
	Color      string  `json:"color"`
	SortOrder  int     `json:"sort_order"`
	IsFavorite bool    `json:"is_favorite"`
	IsArchived bool    `json:"is_archived"`
	IsInbox    bool    `json:"is_inbox"`
	Kind       string  `json:"kind"`
	OpenTasks  int     `json:"open_tasks"`
}

type ProjectInput struct {
	ParentID   *string
	Name       string
	Color      string
	SortOrder  int
	IsFavorite bool
	Kind       string
}

type ProjectUpdate struct {
	ParentID   *string
	Name       *string
	Color      *string
	SortOrder  *int
	IsFavorite *bool
	IsArchived *bool
	Kind       *string
}

func (s *Store) EnsureInboxProject(ctx context.Context, ownerID string) (Project, error) {
	project := Project{ID: newID(), OwnerID: ownerID, Name: "صندوق ورودی", Color: "#2563eb", Kind: "project", IsInbox: true}
	row := s.pool.QueryRow(ctx, `
		INSERT INTO projects (id, owner_id, name, color, kind, is_inbox)
		VALUES ($1, $2, $3, $4, $5, TRUE)
		ON CONFLICT (owner_id) WHERE is_inbox DO UPDATE
		SET owner_id = EXCLUDED.owner_id
		RETURNING id, owner_id, parent_id, name, color, sort_order, is_favorite, is_archived, is_inbox, kind, 0
	`, project.ID, project.OwnerID, project.Name, project.Color, project.Kind)
	if err := scanProject(row, &project); err != nil {
		return Project{}, err
	}
	return project, nil
}

func (s *Store) ListProjects(ctx context.Context, ownerID string) ([]Project, error) {
	if _, err := s.EnsureInboxProject(ctx, ownerID); err != nil {
		return nil, err
	}
	rows, err := s.pool.Query(ctx, `
		SELECT id, owner_id, parent_id, name, color, sort_order, is_favorite, is_archived, is_inbox, kind, 0
		FROM projects
		WHERE owner_id = $1
		ORDER BY is_inbox DESC, is_favorite DESC, sort_order ASC, created_at ASC
	`, ownerID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	projects := []Project{}
	for rows.Next() {
		var project Project
		if err := scanProject(rows, &project); err != nil {
			return nil, err
		}
		projects = append(projects, project)
	}
	return projects, rows.Err()
}

func (s *Store) CreateProject(ctx context.Context, ownerID string, input ProjectInput) (Project, error) {
	project := Project{ID: newID(), OwnerID: ownerID, ParentID: cleanOptional(input.ParentID), Name: cleanName(input.Name), Color: cleanColor(input.Color), SortOrder: input.SortOrder, IsFavorite: input.IsFavorite, Kind: cleanKind(input.Kind)}
	if project.Name == "" {
		return Project{}, ErrProjectNotFound
	}
	row := s.pool.QueryRow(ctx, `
		INSERT INTO projects (id, owner_id, parent_id, name, color, sort_order, is_favorite, kind)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id, owner_id, parent_id, name, color, sort_order, is_favorite, is_archived, is_inbox, kind, 0
	`, project.ID, project.OwnerID, project.ParentID, project.Name, project.Color, project.SortOrder, project.IsFavorite, project.Kind)
	if err := scanProject(row, &project); err != nil {
		return Project{}, err
	}
	return project, nil
}

func (s *Store) UpdateProject(ctx context.Context, ownerID string, id string, input ProjectUpdate) (Project, error) {
	current, err := s.ProjectByID(ctx, ownerID, id)
	if err != nil {
		return Project{}, err
	}
	if current.IsInbox && (input.Name != nil || input.ParentID != nil || input.IsArchived != nil || input.Kind != nil) {
		return Project{}, ErrInboxProject
	}
	name, color, sortOrder, isFavorite, isArchived, kind, parentID := current.Name, current.Color, current.SortOrder, current.IsFavorite, current.IsArchived, current.Kind, current.ParentID
	if input.Name != nil { name = cleanName(*input.Name); if name == "" { return Project{}, ErrProjectNotFound } }
	if input.Color != nil { color = cleanColor(*input.Color) }
	if input.SortOrder != nil { sortOrder = *input.SortOrder }
	if input.IsFavorite != nil { isFavorite = *input.IsFavorite }
	if input.IsArchived != nil { isArchived = *input.IsArchived }
	if input.Kind != nil { kind = cleanKind(*input.Kind) }
	if input.ParentID != nil { parentID = cleanOptional(input.ParentID) }
	var project Project
	row := s.pool.QueryRow(ctx, `
		UPDATE projects
		SET parent_id = $3, name = $4, color = $5, sort_order = $6, is_favorite = $7, is_archived = $8, kind = $9
		WHERE owner_id = $1 AND id = $2
		RETURNING id, owner_id, parent_id, name, color, sort_order, is_favorite, is_archived, is_inbox, kind, 0
	`, ownerID, id, parentID, name, color, sortOrder, isFavorite, isArchived, kind)
	if err := scanProject(row, &project); err != nil { return Project{}, ErrProjectNotFound }
	return project, nil
}

func (s *Store) DeleteProject(ctx context.Context, ownerID string, id string) error {
	project, err := s.ProjectByID(ctx, ownerID, id)
	if err != nil { return err }
	if project.IsInbox { return ErrInboxProject }
	tag, err := s.pool.Exec(ctx, `DELETE FROM projects WHERE owner_id = $1 AND id = $2`, ownerID, id)
	if err != nil { return err }
	if tag.RowsAffected() == 0 { return ErrProjectNotFound }
	return nil
}

func (s *Store) ProjectByID(ctx context.Context, ownerID string, id string) (Project, error) {
	var project Project
	row := s.pool.QueryRow(ctx, `
		SELECT id, owner_id, parent_id, name, color, sort_order, is_favorite, is_archived, is_inbox, kind, 0
		FROM projects WHERE owner_id = $1 AND id = $2
	`, ownerID, id)
	if err := scanProject(row, &project); err != nil { return Project{}, ErrProjectNotFound }
	return project, nil
}

type projectScanner interface{ Scan(dest ...any) error }

func scanProject(row projectScanner, project *Project) error {
	return row.Scan(&project.ID, &project.OwnerID, &project.ParentID, &project.Name, &project.Color, &project.SortOrder, &project.IsFavorite, &project.IsArchived, &project.IsInbox, &project.Kind, &project.OpenTasks)
}

func cleanName(name string) string { return strings.TrimSpace(name) }
func cleanColor(color string) string { color = strings.TrimSpace(color); if color == "" { return "#7c3aed" }; return color }
func cleanKind(kind string) string { if kind == "folder" { return "folder" }; return "project" }
func cleanOptional(value *string) *string { if value == nil { return nil }; cleaned := strings.TrimSpace(*value); if cleaned == "" { return nil }; return &cleaned }
