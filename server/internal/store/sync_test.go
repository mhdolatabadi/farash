package store

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestSyncCursorValidation(t *testing.T) {
	for _, cursor := range []string{"v2.YQ.0", "v1.YQ.-1", "v1.YQ.01", "v1.YQ.9223372036854775808", "v1.Yg.0", "bad"} {
		if _, err := parseSyncCursor("a", cursor); !errors.Is(err, ErrInvalidSync) {
			t.Fatalf("accepted %q: %v", cursor, err)
		}
	}
	if got, err := parseSyncCursor("a", syncCursor("a", 42)); err != nil || got != 42 {
		t.Fatal(got, err)
	}
}

func TestSyncPaginationChangesDeletionAndPrivacy(t *testing.T) {
	ctx := context.Background()
	pool := testPool(t)
	s := New(pool)
	alice, err := s.CreateUser(ctx, "sync-alice@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	bob, err := s.CreateUser(ctx, "sync-bob@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	for _, owner := range []string{alice.ID, bob.ID} {
		if _, err := pool.Exec(ctx, `INSERT INTO projects(id,owner_id,name) VALUES($1,$2,'Private')`, owner+"p", owner); err != nil {
			t.Fatal(err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO tasks(id,owner_id,project_id,title) VALUES($1,$2,$3,$4)`, owner+"t", owner, owner+"p", owner+" secret"); err != nil {
			t.Fatal(err)
		}
	}
	first, err := s.PullSync(ctx, alice.ID, "", 1)
	if err != nil || len(first.Changes) != 1 || !first.HasMore {
		t.Fatal(first, err)
	}
	second, err := s.PullSync(ctx, alice.ID, first.Cursor, 1)
	if err != nil || len(second.Changes) != 1 || second.HasMore {
		t.Fatal(second, err)
	}
	if first.Changes[0].Entity != "projects" || second.Changes[0].Entity != "tasks" {
		t.Fatal(first, second)
	}
	encoded, _ := json.Marshal(second)
	if strings.Contains(string(encoded), bob.ID) || strings.Contains(string(encoded), "password") {
		t.Fatal("foreign or credential data")
	}
	if _, err := s.PullSync(ctx, bob.ID, second.Cursor, 100); !errors.Is(err, ErrInvalidSync) {
		t.Fatal("foreign cursor accepted", err)
	}
	if _, err := s.PullSync(ctx, alice.ID, syncCursor(alice.ID, 9999), 100); !errors.Is(err, ErrInvalidSync) {
		t.Fatal("future cursor accepted", err)
	}
	for _, limit := range []int{-1, 501} {
		if _, err := s.PullSync(ctx, alice.ID, "", limit); !errors.Is(err, ErrInvalidSync) {
			t.Fatal("limit accepted", limit, err)
		}
	}
	for _, title := range []string{"first edit", "latest edit"} {
		if _, err := pool.Exec(ctx, "UPDATE tasks SET title=$2 WHERE id=$1", alice.ID+"t", title); err != nil {
			t.Fatal(err)
		}
	}
	changed, err := s.PullSync(ctx, alice.ID, second.Cursor, 100)
	if err != nil || len(changed.Changes) != 1 || !strings.Contains(string(changed.Changes[0].Data), "latest edit") {
		t.Fatal(changed, err)
	}
	replay, err := s.PullSync(ctx, alice.ID, second.Cursor, 100)
	if err != nil || replay.Cursor != changed.Cursor {
		t.Fatal("read retry", replay, err)
	}
	if _, err := pool.Exec(ctx, "UPDATE tasks SET completed_at=now(),deleted_at=now() WHERE id=$1", alice.ID+"t"); err != nil {
		t.Fatal(err)
	}
	soft, err := s.PullSync(ctx, alice.ID, changed.Cursor, 100)
	if err != nil || len(soft.Changes) != 1 || soft.Changes[0].Operation != "upsert" || !strings.Contains(string(soft.Changes[0].Data), "deleted_at") {
		t.Fatal(soft, err)
	}
	if _, err := pool.Exec(ctx, "DELETE FROM tasks WHERE id=$1", alice.ID+"t"); err != nil {
		t.Fatal(err)
	}
	deleted, err := s.PullSync(ctx, alice.ID, soft.Cursor, 100)
	if err != nil || len(deleted.Changes) != 1 || deleted.Changes[0].Operation != "delete" || deleted.Changes[0].Data != nil {
		t.Fatal(deleted, err)
	}
	if _, err := pool.Exec(ctx, "DELETE FROM users WHERE id=$1", alice.ID); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM sync_changes WHERE owner_id=$1", alice.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("account sync data retained", count, err)
	}
}

func TestSyncDoesNotSkipConcurrentCommitOrRollback(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pool := testPool(t)
	s := New(pool)
	user, err := s.CreateUser(ctx, "sync-order@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO projects(id,owner_id,name) VALUES('p',$1,'Project')`, user.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO tasks(id,owner_id,project_id,title) VALUES('a',$1,'p','A'),('b',$1,'p','B')`, user.ID); err != nil {
		t.Fatal(err)
	}
	initial, err := s.PullSync(ctx, user.ID, "", 100)
	if err != nil {
		t.Fatal(err)
	}
	tx, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback(ctx)
	if _, err := tx.Exec(ctx, "UPDATE tasks SET title='uncommitted' WHERE id='a'"); err != nil {
		t.Fatal(err)
	}
	// A reader must not advance past the uncommitted owner-local revision.
	during, err := s.PullSync(ctx, user.ID, initial.Cursor, 100)
	if err != nil || len(during.Changes) != 0 || during.Cursor != initial.Cursor {
		t.Fatal(during, err)
	}
	done := make(chan error, 1)
	go func() {
		_, err := pool.Exec(ctx, "UPDATE tasks SET title='committed B' WHERE id='b'")
		done <- err
	}()
	if err := tx.Commit(ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	after, err := s.PullSync(ctx, user.ID, during.Cursor, 100)
	if err != nil || len(after.Changes) != 2 {
		t.Fatal("late commit skipped", after, err)
	}
	rollback, err := pool.Begin(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := rollback.Exec(ctx, "UPDATE tasks SET title='must disappear' WHERE id='a'"); err != nil {
		t.Fatal(err)
	}
	if err := rollback.Rollback(ctx); err != nil {
		t.Fatal(err)
	}
	afterRollback, err := s.PullSync(ctx, user.ID, after.Cursor, 100)
	if err != nil || len(afterRollback.Changes) != 0 || afterRollback.Cursor != after.Cursor {
		t.Fatal("rollback emitted change", afterRollback, err)
	}
}
