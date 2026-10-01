package store

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
)

var (
	ErrParentNotFound = errors.New("parent task not found")
	// ErrInvalidParent covers a parent that would make a cycle, nest deeper
	// than maxTaskDepth, sits in another project or section than asked, or is
	// completed while the subtask is open.
	ErrInvalidParent = errors.New("invalid parent task")
)

// maxTaskDepth counts levels including the top-level task: a task with up to
// four levels of subtasks below it.
const maxTaskDepth = 5

// treeLimit bounds every recursive walk, so a damaged row can never make a
// query loop; real trees stay within maxTaskDepth.
const treeLimit = 16

// lockTaskTree serialises hierarchy changes of one owner, so two concurrent
// moves cannot each pass the cycle check and together form a loop.
func lockTaskTree(ctx context.Context, tx pgx.Tx, owner string) error {
	_, err := tx.Exec(ctx, `SELECT pg_advisory_xact_lock(hashtext('farash:task-tree'), hashtext($1))`, owner)
	return err
}

// lockParent loads a live task of the owner to hang a subtask under.
func lockParent(ctx context.Context, tx pgx.Tx, owner, id string) (Task, error) {
	parent, err := scanTask(tx.QueryRow(ctx, `SELECT `+taskColumns+` FROM tasks WHERE owner_id=$1 AND id=$2 AND deleted_at IS NULL FOR UPDATE`, owner, id))
	if errors.Is(err, ErrTaskNotFound) {
		return Task{}, ErrParentNotFound
	}
	return parent, err
}

// taskDepth is the level of a task: 1 for a top-level task.
func taskDepth(ctx context.Context, tx pgx.Tx, owner, id string) (int, error) {
	var depth int
	err := tx.QueryRow(ctx, `
		WITH RECURSIVE up AS (
			SELECT id, parent_id, 1 AS depth FROM tasks WHERE owner_id=$1 AND id=$2
			UNION ALL
			SELECT t.id, t.parent_id, up.depth + 1 FROM tasks t JOIN up ON t.id = up.parent_id
			WHERE t.owner_id=$1 AND up.depth < $3
		) SELECT max(depth) FROM up`, owner, id, treeLimit).Scan(&depth)
	return depth, err
}

// subtreeHeight is the number of levels a task and its live subtasks span:
// 1 for a task without subtasks.
func subtreeHeight(ctx context.Context, tx pgx.Tx, owner, id string) (int, error) {
	var height int
	err := tx.QueryRow(ctx, `
		WITH RECURSIVE down AS (
			SELECT id, 1 AS depth FROM tasks WHERE owner_id=$1 AND id=$2
			UNION ALL
			SELECT t.id, down.depth + 1 FROM tasks t JOIN down ON t.parent_id = down.id
			WHERE t.owner_id=$1 AND t.deleted_at IS NULL AND down.depth < $3
		) SELECT max(depth) FROM down`, owner, id, treeLimit).Scan(&height)
	return height, err
}

// descendantsSQL selects every task below $2 (deleted ones included) for
// owner $1; callers append the statement that uses it.
const descendantsSQL = `
	WITH RECURSIVE down AS (
		SELECT id, 1 AS depth FROM tasks WHERE owner_id=$1 AND parent_id=$2
		UNION ALL
		SELECT t.id, down.depth + 1 FROM tasks t JOIN down ON t.parent_id = down.id
		WHERE t.owner_id=$1 AND down.depth < 16
	)`

func isDescendant(ctx context.Context, tx pgx.Tx, owner, ancestor, candidate string) (bool, error) {
	var found bool
	err := tx.QueryRow(ctx, descendantsSQL+` SELECT EXISTS (SELECT 1 FROM down WHERE id=$3)`, owner, ancestor, candidate).Scan(&found)
	return found, err
}

// checkNewParent verifies that task may move under parent.
func checkNewParent(ctx context.Context, tx pgx.Tx, owner string, task, parent Task) error {
	if parent.ID == task.ID || task.CompletedAt == nil && parent.CompletedAt != nil {
		return ErrInvalidParent
	}
	cycle, err := isDescendant(ctx, tx, owner, task.ID, parent.ID)
	if err != nil {
		return err
	}
	if cycle {
		return ErrInvalidParent
	}
	depth, err := taskDepth(ctx, tx, owner, parent.ID)
	if err != nil {
		return err
	}
	height, err := subtreeHeight(ctx, tx, owner, task.ID)
	if err != nil {
		return err
	}
	if depth+height > maxTaskDepth {
		return ErrInvalidParent
	}
	return nil
}

// moveSubtree keeps every task below id in the given project and section.
func moveSubtree(ctx context.Context, tx pgx.Tx, owner, id, project string, section *string) error {
	_, err := tx.Exec(ctx, descendantsSQL+`
		UPDATE tasks SET project_id=$3, section_id=$4
		WHERE owner_id=$1 AND id IN (SELECT id FROM down)
		AND (project_id IS DISTINCT FROM $3 OR section_id IS DISTINCT FROM $4)`, owner, id, project, section)
	return err
}

// closeSubtree completes the open, live tasks below id at the parent's time,
// so reopening the parent can tell which subtasks closed with it.
func closeSubtree(ctx context.Context, tx pgx.Tx, owner, id string, at time.Time) error {
	_, err := tx.Exec(ctx, descendantsSQL+`
		UPDATE tasks SET completed_at=$3
		WHERE owner_id=$1 AND id IN (SELECT id FROM down) AND completed_at IS NULL AND deleted_at IS NULL`, owner, id, at)
	return err
}

// reopenSubtree reopens the tasks below id that were completed with it.
func reopenSubtree(ctx context.Context, tx pgx.Tx, owner, id string, at time.Time) error {
	_, err := tx.Exec(ctx, descendantsSQL+`
		UPDATE tasks SET completed_at=NULL
		WHERE owner_id=$1 AND id IN (SELECT id FROM down) AND completed_at=$3`, owner, id, at)
	return err
}

// reopenAncestors reopens the completed tasks above id, so an open subtask
// never sits under a completed parent.
func reopenAncestors(ctx context.Context, tx pgx.Tx, owner, id string) error {
	_, err := tx.Exec(ctx, `
		WITH RECURSIVE up AS (
			SELECT parent_id AS id, 1 AS depth FROM tasks WHERE owner_id=$1 AND id=$2 AND parent_id IS NOT NULL
			UNION ALL
			SELECT t.parent_id, up.depth + 1 FROM tasks t JOIN up ON t.id = up.id
			WHERE t.owner_id=$1 AND t.parent_id IS NOT NULL AND up.depth < $3
		)
		UPDATE tasks SET completed_at=NULL WHERE owner_id=$1 AND id IN (SELECT id FROM up) AND completed_at IS NOT NULL`, owner, id, treeLimit)
	return err
}

// deleteSubtree soft-deletes the live tasks below id at the parent's time,
// so restoring the parent brings back exactly those.
func deleteSubtree(ctx context.Context, tx pgx.Tx, owner, id string, at time.Time) error {
	_, err := tx.Exec(ctx, descendantsSQL+`
		UPDATE tasks SET deleted_at=$3
		WHERE owner_id=$1 AND id IN (SELECT id FROM down) AND deleted_at IS NULL`, owner, id, at)
	return err
}

func restoreSubtree(ctx context.Context, tx pgx.Tx, owner, id string, at time.Time) error {
	_, err := tx.Exec(ctx, descendantsSQL+`
		UPDATE tasks SET deleted_at=NULL
		WHERE owner_id=$1 AND id IN (SELECT id FROM down) AND deleted_at=$3`, owner, id, at)
	return err
}
