package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

// InboxName is stored for every Inbox; clients show it in the user's language.
const InboxName = "Inbox"

// MaxProjectDepth is how many levels of nested projects are allowed; a
// top-level project is level 1.
const MaxProjectDepth = 4

var (
	ErrNotFound       = errors.New("not found")
	ErrInboxProtected = errors.New("the inbox cannot be changed this way")
	ErrInvalidParent  = errors.New("invalid parent project")
	ErrInvalidOrder   = errors.New("invalid order")
)

type Project struct {
	ID         string
	ParentID   *string
	Name       string
	Color      string
	IsInbox    bool
	IsFavorite bool
	IsArchived bool
	ChildOrder int
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

type NewProject struct {
	Name       string
	Color      string
	ParentID   *string
	IsFavorite bool
}

// ProjectChanges lists the fields to change; nil fields stay as they are.
type ProjectChanges struct {
	Name       *string
	Color      *string
	IsFavorite *bool
	IsArchived *bool
	// MoveParent moves the project under ParentID, or to the top level when
	// ParentID is nil.
	MoveParent bool
	ParentID   *string
}

const projectColumns = `id, parent_id, name, color, is_inbox, is_favorite, is_archived, child_order, created_at, updated_at`

func scanProject(row pgx.Row) (Project, error) {
	var p Project
	err := row.Scan(&p.ID, &p.ParentID, &p.Name, &p.Color, &p.IsInbox, &p.IsFavorite,
		&p.IsArchived, &p.ChildOrder, &p.CreatedAt, &p.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return Project{}, ErrNotFound
	}
	return p, err
}

// Projects lists the owner's active or archived projects in tree order: the
// Inbox first, then each project followed by its sub-projects, siblings in
// their saved order.
func (s *Store) Projects(ctx context.Context, ownerID string, archived bool) ([]Project, error) {
	rows, err := s.pool.Query(ctx, `
		WITH RECURSIVE tree AS (
			SELECT id, ARRAY[(NOT is_inbox)::int, child_order] AS path FROM projects
			WHERE owner_id = $1 AND parent_id IS NULL
			UNION ALL
			SELECT p.id, t.path || ARRAY[1, p.child_order] FROM projects p
			JOIN tree t ON p.parent_id = t.id
		)
		SELECT `+prefixed("p.", projectColumns)+` FROM projects p JOIN tree USING (id)
		WHERE p.is_archived = $2
		ORDER BY tree.path, p.created_at, p.id
	`, ownerID, archived)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	projects := []Project{}
	for rows.Next() {
		p, err := scanProject(rows)
		if err != nil {
			return nil, err
		}
		projects = append(projects, p)
	}
	return projects, rows.Err()
}

func (s *Store) Project(ctx context.Context, ownerID, id string) (Project, error) {
	return scanProject(s.pool.QueryRow(ctx,
		`SELECT `+projectColumns+` FROM projects WHERE owner_id = $1 AND id = $2`, ownerID, id))
}

// CreateProject adds a project after its siblings.
func (s *Store) CreateProject(ctx context.Context, ownerID string, input NewProject) (Project, error) {
	var project Project
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		if input.ParentID != nil {
			if err := checkParent(ctx, tx, ownerID, *input.ParentID, "", 1); err != nil {
				return err
			}
		}
		var err error
		project, err = scanProject(tx.QueryRow(ctx, `
			INSERT INTO projects (id, owner_id, parent_id, name, color, is_favorite, child_order)
			VALUES ($1, $2, $3, $4, $5, $6, (
				SELECT COALESCE(max(child_order) + 1, 0) FROM projects
				WHERE owner_id = $2 AND parent_id IS NOT DISTINCT FROM $3
			))
			RETURNING `+projectColumns,
			newID(), ownerID, input.ParentID, input.Name, input.Color, input.IsFavorite))
		return err
	})
	return project, err
}

// UpdateProject applies changes to one of the owner's projects. Archiving
// also archives its sub-projects; unarchiving restores the project, its
// sub-projects and its ancestors so that it shows up in the tree again.
func (s *Store) UpdateProject(ctx context.Context, ownerID, id string, changes ProjectChanges) (Project, error) {
	var project Project
	err := pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		current, err := scanProject(tx.QueryRow(ctx,
			`SELECT `+projectColumns+` FROM projects WHERE owner_id = $1 AND id = $2 FOR UPDATE`, ownerID, id))
		if err != nil {
			return err
		}
		if current.IsInbox && (changes.Name != nil || changes.MoveParent || changes.IsArchived != nil) {
			return ErrInboxProtected
		}

		if changes.MoveParent && !sameID(current.ParentID, changes.ParentID) {
			if changes.ParentID != nil {
				height, err := subtreeHeight(ctx, tx, id)
				if err != nil {
					return err
				}
				if err := checkParent(ctx, tx, ownerID, *changes.ParentID, id, height); err != nil {
					return err
				}
			}
			if _, err := tx.Exec(ctx, `
				UPDATE projects SET parent_id = $3, child_order = (
					SELECT COALESCE(max(child_order) + 1, 0) FROM projects
					WHERE owner_id = $1 AND parent_id IS NOT DISTINCT FROM $3
				)
				WHERE owner_id = $1 AND id = $2
			`, ownerID, id, changes.ParentID); err != nil {
				return err
			}
		}

		if _, err := tx.Exec(ctx, `
			UPDATE projects SET
				name = COALESCE($3, name),
				color = COALESCE($4, color),
				is_favorite = COALESCE($5, is_favorite)
			WHERE owner_id = $1 AND id = $2
		`, ownerID, id, changes.Name, changes.Color, changes.IsFavorite); err != nil {
			return err
		}

		if changes.IsArchived != nil {
			if err := setArchived(ctx, tx, ownerID, id, *changes.IsArchived); err != nil {
				return err
			}
		}

		project, err = scanProject(tx.QueryRow(ctx,
			`SELECT `+projectColumns+` FROM projects WHERE owner_id = $1 AND id = $2`, ownerID, id))
		return err
	})
	return project, err
}

// DeleteProject removes a project and, through the foreign keys, its
// sub-projects and everything in them.
func (s *Store) DeleteProject(ctx context.Context, ownerID, id string) error {
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		project, err := scanProject(tx.QueryRow(ctx,
			`SELECT `+projectColumns+` FROM projects WHERE owner_id = $1 AND id = $2 FOR UPDATE`, ownerID, id))
		if err != nil {
			return err
		}
		if project.IsInbox {
			return ErrInboxProtected
		}
		_, err = tx.Exec(ctx, `DELETE FROM projects WHERE owner_id = $1 AND id = $2`, ownerID, id)
		return err
	})
}

// ReorderProjects saves the order of sibling projects: ids[0] comes first.
// Every id must be one of the owner's projects and they must share a parent.
func (s *Store) ReorderProjects(ctx context.Context, ownerID string, ids []string) error {
	if len(ids) == 0 {
		return ErrInvalidOrder
	}
	seen := make(map[string]bool, len(ids))
	for _, id := range ids {
		if seen[id] {
			return ErrInvalidOrder
		}
		seen[id] = true
	}
	return pgx.BeginFunc(ctx, s.pool, func(tx pgx.Tx) error {
		var found, parents int
		if err := tx.QueryRow(ctx, `
			SELECT count(*), count(DISTINCT COALESCE(parent_id, '')) FROM projects
			WHERE owner_id = $1 AND id = ANY($2)
		`, ownerID, ids).Scan(&found, &parents); err != nil {
			return err
		}
		if found != len(ids) {
			return ErrNotFound
		}
		if parents != 1 {
			return ErrInvalidOrder
		}
		_, err := tx.Exec(ctx, `
			UPDATE projects SET child_order = ordered.position - 1
			FROM unnest($2::text[]) WITH ORDINALITY AS ordered(id, position)
			WHERE projects.owner_id = $1 AND projects.id = ordered.id
		`, ownerID, ids)
		return err
	})
}

// checkParent verifies that parentID can hold a subtree of the given height:
// it is the owner's, active, not the Inbox, not inside movingID's subtree, and
// deep enough room is left under MaxProjectDepth.
func checkParent(ctx context.Context, tx pgx.Tx, ownerID, parentID, movingID string, height int) error {
	var isInbox, isArchived bool
	var depth int
	var insideMoving bool
	err := tx.QueryRow(ctx, `
		WITH RECURSIVE ancestors AS (
			SELECT id, parent_id, 1 AS depth FROM projects WHERE owner_id = $1 AND id = $2
			UNION ALL
			SELECT p.id, p.parent_id, a.depth + 1 FROM projects p
			JOIN ancestors a ON p.id = a.parent_id
			WHERE p.owner_id = $1
		)
		SELECT pr.is_inbox, pr.is_archived,
			(SELECT max(depth) FROM ancestors),
			EXISTS (SELECT 1 FROM ancestors WHERE id = $3)
		FROM projects pr WHERE pr.owner_id = $1 AND pr.id = $2
	`, ownerID, parentID, movingID).Scan(&isInbox, &isArchived, &depth, &insideMoving)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrInvalidParent
	}
	if err != nil {
		return err
	}
	if isInbox || isArchived || insideMoving || depth+height > MaxProjectDepth {
		return ErrInvalidParent
	}
	return nil
}

// subtreeHeight is 1 for a project without sub-projects.
func subtreeHeight(ctx context.Context, tx pgx.Tx, id string) (int, error) {
	var height int
	err := tx.QueryRow(ctx, `
		WITH RECURSIVE subtree AS (
			SELECT id, 1 AS level FROM projects WHERE id = $1
			UNION ALL
			SELECT p.id, s.level + 1 FROM projects p JOIN subtree s ON p.parent_id = s.id
		)
		SELECT max(level) FROM subtree
	`, id).Scan(&height)
	return height, err
}

func setArchived(ctx context.Context, tx pgx.Tx, ownerID, id string, archived bool) error {
	// Descendants follow the project either way; ancestors are only restored.
	query := `
		WITH RECURSIVE subtree AS (
			SELECT id FROM projects WHERE owner_id = $1 AND id = $2
			UNION ALL
			SELECT p.id FROM projects p JOIN subtree s ON p.parent_id = s.id
		)
		UPDATE projects SET is_archived = $3
		WHERE owner_id = $1 AND id IN (SELECT id FROM subtree) AND is_archived <> $3`
	if _, err := tx.Exec(ctx, query, ownerID, id, archived); err != nil {
		return err
	}
	if archived {
		return nil
	}
	_, err := tx.Exec(ctx, `
		WITH RECURSIVE ancestors AS (
			SELECT parent_id FROM projects WHERE owner_id = $1 AND id = $2
			UNION ALL
			SELECT p.parent_id FROM projects p JOIN ancestors a ON p.id = a.parent_id
		)
		UPDATE projects SET is_archived = false
		WHERE owner_id = $1 AND id IN (SELECT parent_id FROM ancestors) AND is_archived
	`, ownerID, id)
	return err
}

// prefixed qualifies each column in a comma-separated list, for joins.
func prefixed(prefix, columns string) string {
	parts := strings.Split(columns, ", ")
	for i, part := range parts {
		parts[i] = prefix + part
	}
	return strings.Join(parts, ", ")
}

func sameID(a, b *string) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}
