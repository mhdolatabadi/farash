package store

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	ErrCollaborationNotFound = errors.New("collaboration not found")
	ErrCollaborationInvalid  = errors.New("invalid collaboration input")
	ErrCollaborationConflict = errors.New("collaboration state conflict")
)

type ProjectMember struct {
	UserID string `json:"user_id"`
	Role   string `json:"role"`
}

type ProjectInvitation struct {
	ID          string    `json:"id"`
	ProjectID   string    `json:"project_id"`
	ProjectName string    `json:"project_name"`
	RecipientID string    `json:"recipient_id"`
	Role        string    `json:"role"`
	State       string    `json:"state"`
	ExpiresAt   time.Time `json:"expires_at"`
}

type ProjectCollaboration struct {
	OwnerID     string              `json:"owner_id"`
	Members     []ProjectMember     `json:"members"`
	Invitations []ProjectInvitation `json:"invitations"`
}

type CollaborationCommand struct {
	Email string `json:"email"`
	Role  string `json:"role"`
}

func collaborationRole(role string) bool { return role == "editor" || role == "viewer" }

// ProjectCollaboration deliberately does not authorize task access. Every
// existing project/task endpoint retains its owner-only contract in this phase.
func (s *Store) ProjectCollaboration(ctx context.Context, userID, projectID string) (ProjectCollaboration, error) {
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return ProjectCollaboration{}, err
	}
	defer tx.Rollback(ctx)
	result := ProjectCollaboration{Members: []ProjectMember{}, Invitations: []ProjectInvitation{}}
	err = tx.QueryRow(ctx, `SELECT owner_id FROM projects p WHERE id=$1 AND NOT is_inbox AND kind='project'
		AND (owner_id=$2 OR EXISTS(SELECT 1 FROM project_members m WHERE m.project_id=p.id AND m.user_id=$2))`, projectID, userID).Scan(&result.OwnerID)
	if errors.Is(err, pgx.ErrNoRows) {
		return result, ErrCollaborationNotFound
	}
	if err != nil {
		return result, err
	}
	rows, err := tx.Query(ctx, `SELECT user_id,role FROM project_members WHERE project_id=$1 ORDER BY joined_at,user_id`, projectID)
	if err != nil {
		return result, err
	}
	for rows.Next() {
		var member ProjectMember
		if err := rows.Scan(&member.UserID, &member.Role); err != nil {
			rows.Close()
			return result, err
		}
		result.Members = append(result.Members, member)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return result, err
	}
	if result.OwnerID == userID {
		rows, err = tx.Query(ctx, `SELECT i.id,i.project_id,p.name,i.recipient_id,i.role,i.state,i.expires_at
			FROM project_invitations i JOIN projects p ON p.id=i.project_id WHERE i.project_id=$1 ORDER BY i.created_at,i.id`, projectID)
		if err != nil {
			return result, err
		}
		result.Invitations, err = scanInvitations(rows)
		if err != nil {
			return result, err
		}
	}
	return result, tx.Commit(ctx)
}

func scanInvitations(rows pgx.Rows) ([]ProjectInvitation, error) {
	defer rows.Close()
	result := []ProjectInvitation{}
	for rows.Next() {
		var invite ProjectInvitation
		if err := rows.Scan(&invite.ID, &invite.ProjectID, &invite.ProjectName, &invite.RecipientID, &invite.Role, &invite.State, &invite.ExpiresAt); err != nil {
			return nil, err
		}
		result = append(result, invite)
	}
	return result, rows.Err()
}

func (s *Store) CollaborationInvitations(ctx context.Context, userID string) ([]ProjectInvitation, error) {
	rows, err := s.pool.Query(ctx, `SELECT i.id,i.project_id,p.name,i.recipient_id,i.role,i.state,i.expires_at
		FROM project_invitations i JOIN projects p ON p.id=i.project_id
		WHERE i.recipient_id=$1 AND i.state='pending' AND i.expires_at>now() AND NOT p.is_archived
		AND NOT p.is_inbox AND p.kind='project' ORDER BY i.created_at,i.id`, userID)
	if err != nil {
		return nil, err
	}
	return scanInvitations(rows)
}

func (s *Store) CollaborationWrite(ctx context.Context, userID, projectID, action, id string, in CollaborationCommand) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var owner string
	var archived bool
	// Serialize every membership change before checking current permissions.
	err = tx.QueryRow(ctx, `SELECT owner_id,is_archived FROM projects WHERE id=$1 AND NOT is_inbox AND kind='project' FOR UPDATE`, projectID).Scan(&owner, &archived)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrCollaborationNotFound
	}
	if err != nil {
		return err
	}
	isOwner := owner == userID
	if action == "accept" || action == "decline" {
		var recipient, state, role string
		var expires time.Time
		err = tx.QueryRow(ctx, `SELECT recipient_id,state,role,expires_at FROM project_invitations WHERE id=$1 AND project_id=$2 FOR UPDATE`, id, projectID).Scan(&recipient, &state, &role, &expires)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrCollaborationNotFound
		}
		if err != nil {
			return err
		}
		if recipient != userID {
			return ErrCollaborationNotFound
		}
		if state == "accepted" && action == "accept" {
			return tx.Commit(ctx)
		}
		if state == "declined" && action == "decline" {
			return tx.Commit(ctx)
		}
		if state != "pending" || !expires.After(time.Now()) || archived {
			return ErrCollaborationConflict
		}
		next := "declined"
		if action == "accept" {
			var count int
			if err := tx.QueryRow(ctx, `SELECT count(*) FROM project_members WHERE project_id=$1`, projectID).Scan(&count); err != nil {
				return err
			}
			if count >= 100 {
				return ErrCollaborationConflict
			}
			if _, err := tx.Exec(ctx, `INSERT INTO project_members(project_id,user_id,role) VALUES($1,$2,$3)
				ON CONFLICT(project_id,user_id) DO NOTHING`, projectID, userID, role); err != nil {
				return err
			}
			next = "accepted"
		}
		_, err = tx.Exec(ctx, `UPDATE project_invitations SET state=$2 WHERE id=$1`, id, next)
	} else if action == "leave" {
		if isOwner {
			return ErrCollaborationConflict
		}
		tag, removeErr := tx.Exec(ctx, `DELETE FROM project_members WHERE project_id=$1 AND user_id=$2`, projectID, userID)
		if removeErr != nil {
			return removeErr
		}
		if tag.RowsAffected() == 0 {
			return ErrCollaborationNotFound
		}
		_, err = tx.Exec(ctx, `UPDATE project_invitations SET state='revoked' WHERE project_id=$1 AND recipient_id=$2`, projectID, userID)
	} else {
		if !isOwner {
			return ErrCollaborationNotFound
		}
		if archived {
			return ErrCollaborationConflict
		}
		switch action {
		case "invite":
			if !collaborationRole(in.Role) || len(in.Email) > 254 || strings.TrimSpace(in.Email) == "" {
				return ErrCollaborationInvalid
			}
			var recipient string
			err = tx.QueryRow(ctx, `SELECT id FROM users WHERE email=$1`, NormalizeEmail(in.Email)).Scan(&recipient)
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrCollaborationInvalid
			}
			if err != nil {
				return err
			}
			if recipient == owner {
				return ErrCollaborationInvalid
			}
			var exists bool
			if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM project_members WHERE project_id=$1 AND user_id=$2)`, projectID, recipient).Scan(&exists); err != nil {
				return err
			}
			if exists {
				return ErrCollaborationConflict
			}
			var count int
			if err := tx.QueryRow(ctx, `SELECT count(*) FROM project_invitations WHERE project_id=$1 AND recipient_id<>$2`, projectID, recipient).Scan(&count); err != nil {
				return err
			}
			if count >= 200 {
				return ErrCollaborationConflict
			}
			_, err = tx.Exec(ctx, `INSERT INTO project_invitations(id,project_id,recipient_id,role,expires_at) VALUES($1,$2,$3,$4,now()+interval '7 days')
				ON CONFLICT(project_id,recipient_id) DO UPDATE SET role=EXCLUDED.role,state='pending',expires_at=EXCLUDED.expires_at,created_at=now()`, newID(), projectID, recipient, in.Role)
		case "role":
			if !collaborationRole(in.Role) || id == owner {
				return ErrCollaborationInvalid
			}
			tag, updateErr := tx.Exec(ctx, `UPDATE project_members SET role=$3 WHERE project_id=$1 AND user_id=$2`, projectID, id, in.Role)
			if updateErr != nil {
				return updateErr
			}
			if tag.RowsAffected() == 0 {
				return ErrCollaborationNotFound
			}
		case "remove":
			if id == owner {
				return ErrCollaborationInvalid
			}
			tag, removeErr := tx.Exec(ctx, `DELETE FROM project_members WHERE project_id=$1 AND user_id=$2`, projectID, id)
			if removeErr != nil {
				return removeErr
			}
			if tag.RowsAffected() == 0 {
				return ErrCollaborationNotFound
			}
			_, err = tx.Exec(ctx, `UPDATE project_invitations SET state='revoked' WHERE project_id=$1 AND recipient_id=$2`, projectID, id)
		case "revoke":
			tag, revokeErr := tx.Exec(ctx, `UPDATE project_invitations SET state='revoked' WHERE project_id=$1 AND id=$2 AND state='pending'`, projectID, id)
			if revokeErr != nil {
				return revokeErr
			}
			if tag.RowsAffected() == 0 {
				return ErrCollaborationNotFound
			}
		default:
			return ErrCollaborationInvalid
		}
	}
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}
