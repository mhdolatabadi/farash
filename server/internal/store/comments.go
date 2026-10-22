package store

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"regexp"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/jackc/pgx/v5"
)

var (
	ErrCommentNotFound = errors.New("comment or target not found")
	ErrCommentInvalid  = errors.New("invalid comment input")
	ErrCommentConflict = errors.New("comment state conflict")
	commentRequestKey  = regexp.MustCompile(`^[A-Za-z0-9_-]{8,120}$`)
)

const commentColumns = `id,body,created_at,updated_at,deleted_at`

type Comment struct {
	ID        string     `json:"id"`
	Body      string     `json:"body"`
	CreatedAt time.Time  `json:"created_at"`
	UpdatedAt time.Time  `json:"updated_at"`
	DeletedAt *time.Time `json:"deleted_at"`
}

type CommentPage struct {
	Comments []Comment `json:"comments"`
	Next     string    `json:"next"`
	Total    int       `json:"total"`
}

type CommentInput struct {
	Body       string `json:"body"`
	RequestKey string `json:"request_key"`
}

func scanComment(row pgx.Row) (Comment, error) {
	var out Comment
	err := row.Scan(&out.ID, &out.Body, &out.CreatedAt, &out.UpdatedAt, &out.DeletedAt)
	return out, err
}

func commentTarget(kind string) (string, error) {
	switch kind {
	case "project":
		return "project_id", nil
	case "task":
		return "task_id", nil
	default:
		return "", ErrCommentInvalid
	}
}

// lock is only used by mutations. Parent deletion/archive and task deletion or
// movement cannot pass the permission check concurrently with a comment write.
func commentAccess(ctx context.Context, tx pgx.Tx, owner, kind, target string, lock bool) (bool, error) {
	var archived bool
	var err error
	if kind == "project" {
		query := `SELECT is_archived FROM projects WHERE owner_id=$1 AND id=$2 AND kind='project'`
		if lock {
			query += ` FOR SHARE`
		}
		err = tx.QueryRow(ctx, query, owner, target).Scan(&archived)
	} else {
		query := `SELECT p.is_archived FROM tasks t JOIN projects p ON p.id=t.project_id AND p.owner_id=t.owner_id WHERE t.owner_id=$1 AND t.id=$2 AND t.deleted_at IS NULL`
		if lock {
			query += ` FOR SHARE OF t,p`
		}
		err = tx.QueryRow(ctx, query, owner, target).Scan(&archived)
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrCommentNotFound
	}
	return archived, err
}

// Comments are deliberately private until the complete shared authorization
// boundary is integrated. Pagination retains content-free deletion tombstones.
func (s *Store) ListComments(ctx context.Context, owner, kind, target, after string) (CommentPage, error) {
	out := CommentPage{Comments: []Comment{}}
	column, err := commentTarget(kind)
	if err != nil {
		return out, err
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return out, err
	}
	defer tx.Rollback(ctx)
	if _, err := commentAccess(ctx, tx, owner, kind, target, false); err != nil {
		return out, err
	}
	var cursor time.Time
	if after != "" {
		err = tx.QueryRow(ctx, `SELECT created_at FROM comments WHERE owner_id=$1 AND `+column+`=$2 AND id=$3`, owner, target, after).Scan(&cursor)
		if errors.Is(err, pgx.ErrNoRows) {
			return out, ErrCommentInvalid
		}
		if err != nil {
			return out, err
		}
	}
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM comments WHERE owner_id=$1 AND `+column+`=$2 AND deleted_at IS NULL`, owner, target).Scan(&out.Total); err != nil {
		return out, err
	}
	rows, err := tx.Query(ctx, `SELECT `+commentColumns+` FROM comments WHERE owner_id=$1 AND `+column+`=$2 AND ($3='' OR (created_at,id)>($4::timestamptz,$3)) ORDER BY created_at,id LIMIT 51`, owner, target, after, cursor)
	if err != nil {
		return out, err
	}
	for rows.Next() {
		item, err := scanComment(rows)
		if err != nil {
			rows.Close()
			return out, err
		}
		out.Comments = append(out.Comments, item)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return out, err
	}
	if len(out.Comments) > 50 {
		out.Comments = out.Comments[:50]
		out.Next = out.Comments[49].ID
	}
	return out, tx.Commit(ctx)
}

func (s *Store) WriteComment(ctx context.Context, owner, kind, target, action, id string, in CommentInput) (Comment, error) {
	var out Comment
	column, err := commentTarget(kind)
	if err != nil {
		return out, err
	}
	if action != "create" && action != "edit" && action != "delete" {
		return out, ErrCommentInvalid
	}
	if action != "delete" {
		in.Body = strings.TrimSpace(in.Body)
		if !utf8.ValidString(in.Body) || utf8.RuneCountInString(in.Body) < 1 || utf8.RuneCountInString(in.Body) > 16000 {
			return out, ErrCommentInvalid
		}
	}
	if action == "create" && !commentRequestKey.MatchString(in.RequestKey) {
		return out, ErrCommentInvalid
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return out, err
	}
	defer tx.Rollback(ctx)
	// Serialize per account across targets: a request key cannot race on two
	// different objects, and quota checks cannot be bypassed by parallel creates.
	if _, err = tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,1827))`, owner); err != nil {
		return out, err
	}
	archived, err := commentAccess(ctx, tx, owner, kind, target, true)
	if err != nil {
		return out, err
	}
	if archived {
		return out, ErrCommentConflict
	}
	changed := action != "create"
	switch action {
	case "create":
		digest := sha256.Sum256([]byte(in.Body))
		hash := hex.EncodeToString(digest[:])
		var storedHash string
		err = tx.QueryRow(ctx, `SELECT request_hash FROM comments WHERE owner_id=$1 AND request_key=$2`, owner, in.RequestKey).Scan(&storedHash)
		if err == nil {
			out, err = scanComment(tx.QueryRow(ctx, `SELECT `+commentColumns+` FROM comments WHERE owner_id=$1 AND request_key=$2 AND `+column+`=$3`, owner, in.RequestKey, target))
			if errors.Is(err, pgx.ErrNoRows) || storedHash != hash {
				return out, ErrCommentConflict
			}
		} else if errors.Is(err, pgx.ErrNoRows) {
			changed = true
			var count int
			if err = tx.QueryRow(ctx, `SELECT count(*) FROM comments WHERE owner_id=$1 AND `+column+`=$2`, owner, target).Scan(&count); err != nil {
				return out, err
			}
			if count >= 5000 {
				return out, ErrCommentConflict
			}
			out, err = scanComment(tx.QueryRow(ctx, `INSERT INTO comments(id,owner_id,`+column+`,body,request_key,request_hash) VALUES($1,$2,$3,$4,$5,$6) RETURNING `+commentColumns, newID(), owner, target, in.Body, in.RequestKey, hash))
		}
	case "edit":
		out, err = scanComment(tx.QueryRow(ctx, `UPDATE comments SET body=$4,updated_at=clock_timestamp() WHERE owner_id=$1 AND `+column+`=$2 AND id=$3 AND deleted_at IS NULL RETURNING `+commentColumns, owner, target, id, in.Body))
	case "delete":
		out, err = scanComment(tx.QueryRow(ctx, `UPDATE comments SET body='',deleted_at=COALESCE(deleted_at,clock_timestamp()),updated_at=CASE WHEN deleted_at IS NULL THEN clock_timestamp() ELSE updated_at END WHERE owner_id=$1 AND `+column+`=$2 AND id=$3 RETURNING `+commentColumns, owner, target, id))
	}
	if errors.Is(err, pgx.ErrNoRows) {
		return out, ErrCommentNotFound
	}
	if err != nil {
		return out, err
	}
	if kind == "task" && changed {
		// A comment is user history on the task. Invalidate version-based
		// destructive undo guards, including an untouched recurring successor.
		if _, err = tx.Exec(ctx, `UPDATE tasks SET updated_at=clock_timestamp() WHERE owner_id=$1 AND id=$2`, owner, target); err != nil {
			return out, err
		}
	}
	return out, tx.Commit(ctx)
}
