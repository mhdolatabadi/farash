package store

import (
	"context"
	"errors"
	"github.com/jackc/pgx/v5"
	"strings"
	"time"
)

var ErrAgileNotFound = errors.New("agile object not found")
var ErrAgileInvalid = errors.New("invalid agile input")
var ErrAgileConflict = errors.New("agile state conflict")

type AgileCommand struct {
	Method     string  `json:"method"`
	RequestKey string  `json:"request_key"`
	Name       string  `json:"name"`
	Goal       string  `json:"goal"`
	StartsOn   string  `json:"starts_on"`
	EndsOn     string  `json:"ends_on"`
	Capacity   *int    `json:"capacity"`
	SprintID   *string `json:"sprint_id"`
	IssueType  string  `json:"issue_type"`
	Points     *int    `json:"points"`
	Acceptance string  `json:"acceptance"`
	Stage      string  `json:"stage"`
	Review     string  `json:"review"`
	Retro      string  `json:"retro"`
}
type Sprint struct {
	ID              string     `json:"id"`
	Name            string     `json:"name"`
	Goal            string     `json:"goal"`
	StartsOn        string     `json:"starts_on"`
	EndsOn          string     `json:"ends_on"`
	Capacity        *int       `json:"capacity"`
	State           string     `json:"state"`
	StartedAt       *time.Time `json:"started_at"`
	ClosedAt        *time.Time `json:"closed_at"`
	CommittedPoints int        `json:"committed_points"`
	CommittedCount  int        `json:"committed_count"`
	ScopePoints     int        `json:"scope_points"`
	DonePoints      int        `json:"done_points"`
	ScopeCount      int        `json:"scope_count"`
	DoneCount       int        `json:"done_count"`
	Unestimated     int        `json:"unestimated"`
	TrackedSeconds  int64      `json:"tracked_seconds"`
	Review          string     `json:"review"`
	Retro           string     `json:"retro"`
}
type AgileItem struct {
	Task       Task    `json:"task"`
	IssueType  string  `json:"issue_type"`
	Points     *int    `json:"points"`
	SprintID   *string `json:"sprint_id"`
	Acceptance string  `json:"acceptance"`
	Stage      string  `json:"stage"`
}
type SprintEvent struct {
	SprintID        string    `json:"sprint_id"`
	At              time.Time `json:"at"`
	Kind            string    `json:"kind"`
	ScopePoints     int       `json:"scope_points"`
	RemainingPoints int       `json:"remaining_points"`
	ScopeCount      int       `json:"scope_count"`
	RemainingCount  int       `json:"remaining_count"`
}
type SprintScope struct {
	SprintID  string     `json:"sprint_id"`
	TaskID    string     `json:"task_id"`
	Title     string     `json:"title"`
	Points    *int       `json:"points"`
	Completed bool       `json:"completed"`
	RemovedAt *time.Time `json:"removed_at"`
}
type AgileWorkspace struct {
	Method  string        `json:"method"`
	Items   []AgileItem   `json:"items"`
	Sprints []Sprint      `json:"sprints"`
	Events  []SprintEvent `json:"events"`
	Scope   []SprintScope `json:"scope"`
}

func agileProject(ctx context.Context, tx pgx.Tx, owner, project string, lock bool) (string, error) {
	suffix := ""
	if lock {
		suffix = " FOR UPDATE"
	}
	var method string
	err := tx.QueryRow(ctx, `SELECT method FROM projects WHERE owner_id=$1 AND id=$2 AND kind='project' AND NOT is_inbox`+suffix, owner, project).Scan(&method)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrAgileNotFound
	}
	return method, err
}
func (s *Store) AgileWorkspace(ctx context.Context, owner, project string) (AgileWorkspace, error) {
	out := AgileWorkspace{Items: []AgileItem{}, Sprints: []Sprint{}, Events: []SprintEvent{}, Scope: []SprintScope{}}
	tx, err := s.pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return out, err
	}
	defer tx.Rollback(ctx)
	if out.Method, err = agileProject(ctx, tx, owner, project, false); err != nil {
		return out, err
	}
	rows, err := tx.Query(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND project_id=$2 AND deleted_at IS NULL ORDER BY sort_order,created_at,id`, owner, project)
	if err != nil {
		return out, err
	}
	for rows.Next() {
		t, e := scanTask(rows)
		if e != nil {
			rows.Close()
			return out, e
		}
		out.Items = append(out.Items, AgileItem{Task: t, IssueType: "task", Stage: "todo"})
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return out, err
	}
	rows, err = tx.Query(ctx, `SELECT m.task_id,m.issue_type,m.points,m.sprint_id,m.acceptance,m.stage FROM scrum_items m JOIN tasks t ON t.id=m.task_id WHERE m.owner_id=$1 AND t.owner_id=$1 AND t.project_id=$2 AND t.deleted_at IS NULL`, owner, project)
	if err != nil {
		return out, err
	}
	meta := map[string]AgileItem{}
	for rows.Next() {
		var id string
		var m AgileItem
		if err = rows.Scan(&id, &m.IssueType, &m.Points, &m.SprintID, &m.Acceptance, &m.Stage); err != nil {
			rows.Close()
			return out, err
		}
		meta[id] = m
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return out, err
	}
	for i, item := range out.Items {
		if m, ok := meta[item.Task.ID]; ok {
			m.Task = item.Task
			out.Items[i] = m
		}
	}
	rows, err = tx.Query(ctx, `SELECT s.id,s.name,s.goal,to_char(s.starts_on,'YYYY-MM-DD'),to_char(s.ends_on,'YYYY-MM-DD'),s.capacity,s.state,s.started_at,s.closed_at,s.committed_points,s.committed_count,
 COALESCE((SELECT sum(points) FROM sprint_scope WHERE sprint_id=s.id AND removed_at IS NULL),0),
 COALESCE((SELECT sum(points) FROM sprint_scope WHERE sprint_id=s.id AND removed_at IS NULL AND completed),0),
 (SELECT count(*) FROM sprint_scope WHERE sprint_id=s.id AND removed_at IS NULL),
 (SELECT count(*) FROM sprint_scope WHERE sprint_id=s.id AND removed_at IS NULL AND completed),
 (SELECT count(*) FROM sprint_scope WHERE sprint_id=s.id AND removed_at IS NULL AND points IS NULL),
 CASE WHEN s.state='closed' THEN s.closed_tracked_seconds ELSE sprint_tracked_seconds(s.id) END,s.review,s.retro
 FROM sprints s WHERE s.owner_id=$1 AND s.project_id=$2 ORDER BY s.created_at DESC,s.id`, owner, project)
	if err != nil {
		return out, err
	}
	for rows.Next() {
		var v Sprint
		if err = rows.Scan(&v.ID, &v.Name, &v.Goal, &v.StartsOn, &v.EndsOn, &v.Capacity, &v.State, &v.StartedAt, &v.ClosedAt, &v.CommittedPoints, &v.CommittedCount, &v.ScopePoints, &v.DonePoints, &v.ScopeCount, &v.DoneCount, &v.Unestimated, &v.TrackedSeconds, &v.Review, &v.Retro); err != nil {
			rows.Close()
			return out, err
		}
		out.Sprints = append(out.Sprints, v)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return out, err
	}
	rows, err = tx.Query(ctx, `SELECT e.sprint_id,e.at,e.kind,e.scope_points,e.remaining_points,e.scope_count,e.remaining_count FROM sprint_events e JOIN sprints s ON s.id=e.sprint_id WHERE s.owner_id=$1 AND s.project_id=$2 ORDER BY e.id`, owner, project)
	if err != nil {
		return out, err
	}
	for rows.Next() {
		var v SprintEvent
		if err = rows.Scan(&v.SprintID, &v.At, &v.Kind, &v.ScopePoints, &v.RemainingPoints, &v.ScopeCount, &v.RemainingCount); err != nil {
			rows.Close()
			return out, err
		}
		out.Events = append(out.Events, v)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return out, err
	}
	rows, err = tx.Query(ctx, `SELECT sc.sprint_id,sc.task_id,sc.title,sc.points,sc.completed,sc.removed_at FROM sprint_scope sc JOIN sprints s ON s.id=sc.sprint_id WHERE s.owner_id=$1 AND s.project_id=$2 ORDER BY s.created_at,sc.task_id`, owner, project)
	if err != nil {
		return out, err
	}
	for rows.Next() {
		var v SprintScope
		if err = rows.Scan(&v.SprintID, &v.TaskID, &v.Title, &v.Points, &v.Completed, &v.RemovedAt); err != nil {
			rows.Close()
			return out, err
		}
		out.Scope = append(out.Scope, v)
	}
	err = rows.Err()
	rows.Close()
	if err != nil {
		return out, err
	}
	return out, tx.Commit(ctx)
}
func validSprint(in AgileCommand) bool {
	a, e := time.Parse(dateLayout, in.StartsOn)
	b, f := time.Parse(dateLayout, in.EndsOn)
	return strings.TrimSpace(in.Name) != "" && len([]rune(in.Name)) <= 120 && len([]rune(in.Goal)) <= 4000 && e == nil && f == nil && !b.Before(a) && b.Sub(a) <= 90*24*time.Hour && (in.Capacity == nil || *in.Capacity >= 0 && *in.Capacity <= 10000)
}

// All lifecycle writes take the project lock first, including starts from two devices.
func (s *Store) AgileWrite(ctx context.Context, owner, project, action, id string, in AgileCommand) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	method, err := agileProject(ctx, tx, owner, project, true)
	if err != nil {
		return err
	}
	var archived bool
	if err = tx.QueryRow(ctx, `SELECT is_archived FROM projects WHERE id=$1`, project).Scan(&archived); err != nil {
		return err
	}
	if archived {
		return ErrAgileConflict
	}
	if action == "method" {
		if in.Method != "simple" && in.Method != "kanban" && in.Method != "scrum" {
			return ErrAgileInvalid
		}
		var active bool
		if err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM sprints WHERE project_id=$1 AND state='active')`, project).Scan(&active); err != nil {
			return err
		}
		if active && in.Method != "scrum" {
			return ErrAgileConflict
		}
		_, err = tx.Exec(ctx, `UPDATE projects SET method=$3 WHERE id=$1 AND owner_id=$2`, project, owner, in.Method)
	} else if method == "simple" {
		return ErrAgileConflict
	} else if action == "item" {
		err = writeAgileItem(ctx, tx, owner, project, id, in)
	} else {
		if method != "scrum" {
			return ErrAgileConflict
		}
		switch action {
		case "create":
			if !validSprint(in) || len(in.RequestKey) < 8 || len(in.RequestKey) > 100 {
				return ErrAgileInvalid
			}
			var oldID, oldName, oldGoal, a, b string
			var capacity *int
			e := tx.QueryRow(ctx, `SELECT id,name,goal,to_char(starts_on,'YYYY-MM-DD'),to_char(ends_on,'YYYY-MM-DD'),capacity FROM sprints WHERE owner_id=$1 AND project_id=$2 AND request_key=$3`, owner, project, in.RequestKey).Scan(&oldID, &oldName, &oldGoal, &a, &b, &capacity)
			if e == nil {
				if oldName != strings.TrimSpace(in.Name) || oldGoal != in.Goal || a != in.StartsOn || b != in.EndsOn || !sameInt(capacity, in.Capacity) {
					return ErrAgileInvalid
				}
				return tx.Commit(ctx)
			}
			if !errors.Is(e, pgx.ErrNoRows) {
				return e
			}
			_, err = tx.Exec(ctx, `INSERT INTO sprints(id,owner_id,project_id,request_key,name,goal,starts_on,ends_on,capacity)VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`, newID(), owner, project, in.RequestKey, strings.TrimSpace(in.Name), in.Goal, in.StartsOn, in.EndsOn, in.Capacity)
		default:
			var state string
			err = tx.QueryRow(ctx, `SELECT state FROM sprints WHERE id=$1 AND owner_id=$2 AND project_id=$3 FOR UPDATE`, id, owner, project).Scan(&state)
			if errors.Is(err, pgx.ErrNoRows) {
				return ErrAgileNotFound
			}
			if err != nil {
				return err
			}
			switch action {
			case "edit":
				if state != "planned" {
					return ErrAgileConflict
				}
				if !validSprint(in) {
					return ErrAgileInvalid
				}
				_, err = tx.Exec(ctx, `UPDATE sprints SET name=$2,goal=$3,starts_on=$4,ends_on=$5,capacity=$6 WHERE id=$1`, id, strings.TrimSpace(in.Name), in.Goal, in.StartsOn, in.EndsOn, in.Capacity)
			case "start":
				if state == "active" {
					return tx.Commit(ctx)
				}
				if state != "planned" {
					return ErrAgileConflict
				}
				var exists bool
				err = tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM sprints WHERE project_id=$1 AND state='active')`, project).Scan(&exists)
				if err != nil {
					return err
				}
				if exists {
					return ErrAgileConflict
				}
				_, err = tx.Exec(ctx, `UPDATE scrum_items m SET sprint_id=NULL FROM tasks t WHERE t.id=m.task_id AND m.sprint_id=$1 AND (t.completed_at IS NOT NULL OR t.deleted_at IS NOT NULL OR t.project_id<>$2)`, id, project)
				if err != nil {
					return err
				}
				_, err = tx.Exec(ctx, `INSERT INTO sprint_scope(sprint_id,task_id,title,points,completed) SELECT $1,t.id,t.title,m.points,false FROM scrum_items m JOIN tasks t ON t.id=m.task_id WHERE m.sprint_id=$1 AND m.owner_id=$2 AND t.owner_id=$2 AND t.project_id=$3 AND t.completed_at IS NULL AND t.deleted_at IS NULL`, id, owner, project)
				if err != nil {
					return err
				}
				var count int
				if err = tx.QueryRow(ctx, `SELECT count(*) FROM sprint_scope WHERE sprint_id=$1`, id).Scan(&count); err != nil {
					return err
				}
				if count == 0 {
					return ErrAgileInvalid
				}
				_, err = tx.Exec(ctx, `UPDATE sprints SET state='active',started_at=clock_timestamp(),committed_points=(SELECT COALESCE(sum(points),0) FROM sprint_scope WHERE sprint_id=$1),committed_count=$2 WHERE id=$1`, id, count)
				if err == nil {
					_, err = tx.Exec(ctx, `SELECT record_sprint_event($1,'start')`, id)
				}
			case "close":
				if state == "closed" {
					return tx.Commit(ctx)
				}
				if state != "active" {
					return ErrAgileConflict
				}
				if len([]rune(in.Review)) > 20000 || len([]rune(in.Retro)) > 20000 {
					return ErrAgileInvalid
				}
				if in.SprintID != nil {
					var target string
					err = tx.QueryRow(ctx, `SELECT id FROM sprints WHERE id=$1 AND project_id=$2 AND owner_id=$3 AND state='planned'`, *in.SprintID, project, owner).Scan(&target)
					if errors.Is(err, pgx.ErrNoRows) {
						return ErrAgileNotFound
					}
					if err != nil {
						return err
					}
				}
				_, err = tx.Exec(ctx, `SELECT record_sprint_event($1,'close')`, id)
				if err != nil {
					return err
				}
				_, err = tx.Exec(ctx, `UPDATE sprints SET state='closed',closed_at=clock_timestamp(),review=$2,retro=$3 WHERE id=$1`, id, in.Review, in.Retro)
				if err != nil {
					return err
				}
				_, err = tx.Exec(ctx, `UPDATE sprints SET closed_tracked_seconds=sprint_tracked_seconds(id) WHERE id=$1`, id)
				if err != nil {
					return err
				}
				_, err = tx.Exec(ctx, `UPDATE scrum_items m SET sprint_id=$2,stage='todo' FROM tasks t WHERE m.task_id=t.id AND m.sprint_id=$1 AND (t.completed_at IS NULL OR t.deleted_at IS NOT NULL OR t.project_id<>$3)`, id, in.SprintID, project)
			case "notes":
				if len([]rune(in.Review)) > 20000 || len([]rune(in.Retro)) > 20000 {
					return ErrAgileInvalid
				}
				_, err = tx.Exec(ctx, `UPDATE sprints SET review=$2,retro=$3 WHERE id=$1`, id, in.Review, in.Retro)
			default:
				return ErrAgileInvalid
			}
		}
	}
	if err != nil {
		return err
	}
	return tx.Commit(ctx)
}
func sameInt(a, b *int) bool { return a == nil && b == nil || a != nil && b != nil && *a == *b }
func writeAgileItem(ctx context.Context, tx pgx.Tx, owner, project, id string, in AgileCommand) error {
	if in.IssueType != "task" && in.IssueType != "story" && in.IssueType != "bug" && in.IssueType != "epic" {
		return ErrAgileInvalid
	}
	if in.Stage != "todo" && in.Stage != "doing" {
		return ErrAgileInvalid
	}
	if in.Points != nil && (*in.Points < 0 || *in.Points > 1000) || len([]rune(in.Acceptance)) > 20000 || in.IssueType == "epic" && in.SprintID != nil {
		return ErrAgileInvalid
	}
	var completed bool
	err := tx.QueryRow(ctx, `SELECT completed_at IS NOT NULL FROM tasks WHERE id=$1 AND owner_id=$2 AND project_id=$3 AND deleted_at IS NULL`, id, owner, project).Scan(&completed)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrAgileNotFound
	}
	if err != nil {
		return err
	}
	var oldSprint *string
	var oldPoints *int
	err = tx.QueryRow(ctx, `SELECT sprint_id,points FROM scrum_items WHERE task_id=$1 AND owner_id=$2`, id, owner).Scan(&oldSprint, &oldPoints)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if oldSprint != nil {
		var state string
		if err = tx.QueryRow(ctx, `SELECT state FROM sprints WHERE id=$1`, *oldSprint).Scan(&state); err != nil {
			return err
		}
		if state == "active" && !sameInt(oldPoints, in.Points) {
			return ErrAgileConflict
		}
	}
	targetState := ""
	if in.SprintID != nil {
		if completed && (oldSprint == nil || *oldSprint != *in.SprintID) {
			return ErrAgileConflict
		}
		err = tx.QueryRow(ctx, `SELECT state FROM sprints WHERE id=$1 AND owner_id=$2 AND project_id=$3 AND state<>'closed'`, *in.SprintID, owner, project).Scan(&targetState)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrAgileNotFound
		}
		if err != nil {
			return err
		}
	}
	_, err = tx.Exec(ctx, `INSERT INTO scrum_items(task_id,owner_id,sprint_id,issue_type,points,acceptance,stage) VALUES($1,$2,$3,$4,$5,$6,$7) ON CONFLICT(task_id) DO UPDATE SET sprint_id=EXCLUDED.sprint_id,issue_type=EXCLUDED.issue_type,points=EXCLUDED.points,acceptance=EXCLUDED.acceptance,stage=EXCLUDED.stage WHERE scrum_items.owner_id=EXCLUDED.owner_id`, id, owner, in.SprintID, in.IssueType, in.Points, in.Acceptance, in.Stage)
	if err != nil {
		return err
	}
	changed := oldSprint == nil && in.SprintID != nil || oldSprint != nil && (in.SprintID == nil || *oldSprint != *in.SprintID)
	if changed && oldSprint != nil {
		var active bool
		if err = tx.QueryRow(ctx, `SELECT state='active' FROM sprints WHERE id=$1`, *oldSprint).Scan(&active); err != nil {
			return err
		}
		if active {
			_, err = tx.Exec(ctx, `UPDATE sprint_scope SET removed_at=clock_timestamp() WHERE sprint_id=$1 AND task_id=$2`, *oldSprint, id)
			if err == nil {
				_, err = tx.Exec(ctx, `SELECT record_sprint_event($1,'scope_removed')`, *oldSprint)
			}
			if err != nil {
				return err
			}
		}
	}
	if changed && targetState == "active" {
		_, err = tx.Exec(ctx, `INSERT INTO sprint_scope(sprint_id,task_id,title,points,completed) SELECT $1,id,title,$3,false FROM tasks WHERE id=$2 ON CONFLICT(sprint_id,task_id) DO UPDATE SET points=EXCLUDED.points,title=EXCLUDED.title,removed_at=NULL,completed=false`, *in.SprintID, id, in.Points)
		if err == nil {
			_, err = tx.Exec(ctx, `SELECT record_sprint_event($1,'scope_added')`, *in.SprintID)
		}
	}
	return err
}
