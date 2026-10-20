package store

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
)

var ErrInvalidSync = errors.New("invalid sync cursor or page size")

// SyncChange is a latest row image or a minimal hard-deletion tombstone.
// Revisions are strings to avoid JavaScript integer precision loss.
type SyncChange struct {
	Entity    string          `json:"entity"`
	ID        string          `json:"id"`
	Revision  string          `json:"revision"`
	Operation string         `json:"operation"`
	Data      json.RawMessage `json:"data"`
}

type SyncPage struct {
	Version int          `json:"version"`
	Cursor  string       `json:"cursor"`
	HasMore bool         `json:"has_more"`
	Changes []SyncChange `json:"changes"`
}

func syncCursor(owner string, revision int64) string {
	return "v1." + base64.RawURLEncoding.EncodeToString([]byte(owner)) + "." + strconv.FormatInt(revision, 10)
}

func parseSyncCursor(owner, cursor string) (int64, error) {
	if cursor == "" {
		return 0, nil
	}
	parts := strings.Split(cursor, ".")
	if len(parts) != 3 || parts[0] != "v1" || parts[1] != base64.RawURLEncoding.EncodeToString([]byte(owner)) {
		return 0, ErrInvalidSync
	}
	revision, err := strconv.ParseInt(parts[2], 10, 64)
	if err != nil || revision < 0 || strconv.FormatInt(revision, 10) != parts[2] {
		return 0, ErrInvalidSync
	}
	return revision, nil
}

// PullSync returns committed current-state changes for one owner only. The
// revision allocator is transactional and serializes writes per owner. Never
// replace it with a global sequence: that can skip transactions committing late.
func (s *Store) PullSync(ctx context.Context, owner, cursor string, limit int) (SyncPage, error) {
	revision, err := parseSyncCursor(owner, cursor)
	if err != nil {
		return SyncPage{}, err
	}
	if limit == 0 {
		limit = 100
	}
	if limit < 1 || limit > 500 {
		return SyncPage{}, ErrInvalidSync
	}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return SyncPage{}, err
	}
	defer tx.Rollback(ctx)
	var head int64
	if err := tx.QueryRow(ctx, `SELECT COALESCE((SELECT revision FROM sync_versions WHERE owner_id=$1),0)`, owner).Scan(&head); err != nil {
		return SyncPage{}, err
	}
	if revision > head {
		return SyncPage{}, ErrInvalidSync
	}
	rows, err := tx.Query(ctx, `SELECT entity,entity_id,revision,operation,data FROM sync_changes WHERE owner_id=$1 AND revision>$2 ORDER BY revision LIMIT $3`, owner, revision, limit+1)
	if err != nil {
		return SyncPage{}, err
	}
	page := SyncPage{Version: 1, Cursor: syncCursor(owner, revision), Changes: []SyncChange{}}
	for rows.Next() {
		var change SyncChange
		var rev int64
		var raw []byte
		if err := rows.Scan(&change.Entity, &change.ID, &rev, &change.Operation, &raw); err != nil {
			rows.Close()
			return SyncPage{}, err
		}
		if len(page.Changes) == limit {
			page.HasMore = true
			break
		}
		change.Revision = strconv.FormatInt(rev, 10)
		change.Data = json.RawMessage(raw)
		page.Changes = append(page.Changes, change)
		page.Cursor = syncCursor(owner, rev)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return SyncPage{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return SyncPage{}, err
	}
	return page, nil
}
