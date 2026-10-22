package store

import (
	"context"
	"encoding/json"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

var ErrExportTooLarge = errors.New("export exceeds synchronous download limit")

const (
	exportMaxRecords = 100000
	exportMaxBytes   = 32 * 1024 * 1024
)

type accountExport struct {
	Format      string                       `json:"format"`
	Version     int                          `json:"version"`
	ExportedAt  time.Time                    `json:"exported_at"`
	Preferences json.RawMessage              `json:"preferences"`
	Records     map[string][]json.RawMessage `json:"records"`
}

// Explicit version-1 field lists prevent future private/internal columns from
// silently becoming part of the portable contract.
var exportQueries = []struct {
	name  string
	query string
}{
	{"projects", `SELECT to_jsonb(x) FROM (SELECT id,parent_id,name,color,sort_order,is_favorite,is_archived,is_inbox,kind,method,created_at,updated_at FROM projects WHERE owner_id=$1) x ORDER BY id LIMIT 100001`},
	{"sections", `SELECT to_jsonb(x) FROM (SELECT id,project_id,name,sort_order,is_collapsed,created_at,updated_at FROM sections WHERE owner_id=$1) x ORDER BY id LIMIT 100001`},
	{"tasks", `SELECT to_jsonb(x) FROM (SELECT id,project_id,section_id,parent_id,title,description,priority,sort_order,completed_at,deleted_at,due_date,due_at,due_timezone,deadline,duration_minutes,created_at,updated_at FROM tasks WHERE owner_id=$1) x ORDER BY id LIMIT 100001`},
	{"labels", `SELECT to_jsonb(x) FROM (SELECT id,name,color,is_favorite,sort_order,created_at,updated_at FROM labels WHERE owner_id=$1) x ORDER BY id LIMIT 100001`},
	{"task_labels", `SELECT to_jsonb(x) FROM (SELECT task_id,label_id FROM task_labels WHERE owner_id=$1) x ORDER BY task_id,label_id LIMIT 100001`},
	{"time_entries", `SELECT to_jsonb(x) FROM (SELECT id,task_id,task_title,started_at,ended_at,planned_end,source,request_key,created_at,updated_at FROM time_entries WHERE owner_id=$1) x ORDER BY id LIMIT 100001`},
	{"sprints", `SELECT to_jsonb(x) FROM (SELECT id,project_id,request_key,name,goal,starts_on,ends_on,capacity,state,started_at,closed_at,committed_points,committed_count,closed_tracked_seconds,review,retro,created_at FROM sprints WHERE owner_id=$1) x ORDER BY id LIMIT 100001`},
	{"scrum_items", `SELECT to_jsonb(x) FROM (SELECT task_id,sprint_id,issue_type,points,acceptance,stage FROM scrum_items WHERE owner_id=$1) x ORDER BY task_id LIMIT 100001`},
	{"sprint_scope", `SELECT to_jsonb(x) FROM (SELECT sc.sprint_id,sc.task_id,sc.title,sc.points,sc.completed,sc.removed_at FROM sprint_scope sc JOIN sprints s ON s.id=sc.sprint_id WHERE s.owner_id=$1) x ORDER BY sprint_id,task_id LIMIT 100001`},
	{"sprint_events", `SELECT to_jsonb(x) FROM (SELECT e.id,e.sprint_id,e.at,e.kind,e.scope_points,e.remaining_points,e.scope_count,e.remaining_count FROM sprint_events e JOIN sprints s ON s.id=e.sprint_id WHERE s.owner_id=$1) x ORDER BY id LIMIT 100001`},
}

// ExportAccount returns a bounded, consistent snapshot, including completed and
// deleted tasks. It never exports users, password hashes, sessions or tokens.
func (s *Store) ExportAccount(ctx context.Context, owner string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)
	document := accountExport{Format: "farash-export", Version: 1, Records: map[string][]json.RawMessage{}}
	err = tx.QueryRow(ctx, `SELECT transaction_timestamp(),jsonb_build_object('weekly_active_days',weekly_active_days,'weekly_task_goal',weekly_task_goal) FROM users WHERE id=$1`, owner).Scan(&document.ExportedAt, &document.Preferences)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrUserNotFound
	}
	if err != nil {
		return nil, err
	}
	document.ExportedAt = document.ExportedAt.UTC()
	budget := exportBudget{bytes: len(document.Preferences)}
	for _, table := range exportQueries {
		document.Records[table.name] = []json.RawMessage{}
		rows, err := tx.Query(ctx, table.query, owner)
		if err != nil {
			return nil, err
		}
		for rows.Next() {
			var record json.RawMessage
			if err := rows.Scan(&record); err != nil {
				rows.Close()
				return nil, err
			}
			if budget.add(record) != nil {
				rows.Close()
				return nil, ErrExportTooLarge
			}
			document.Records[table.name] = append(document.Records[table.name], record)
		}
		rows.Close()
		if err := rows.Err(); err != nil {
			return nil, err
		}
	}
	body, err := json.Marshal(document)
	if err != nil {
		return nil, err
	}
	if len(body) > exportMaxBytes {
		return nil, ErrExportTooLarge
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return body, nil
}

type exportBudget struct {
	records int
	bytes   int
}

func (b *exportBudget) add(record []byte) error {
	b.records++
	b.bytes += len(record) + 1
	if b.records > exportMaxRecords || b.bytes > exportMaxBytes {
		return ErrExportTooLarge
	}
	return nil
}
