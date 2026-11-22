package store

import (
	"context"
	"sync"
	"testing"
	"time"
)

func TestConcurrentTaskCreateRetriesAreOneTask(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	pool := testPool(t)
	s := New(pool)
	owner, err := s.CreateUser(ctx, "task-create-parallel@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	inbox, err := s.EnsureInboxProject(ctx, owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	const retries = 8
	results := make([]Task, retries)
	failures := make([]error, retries)
	var wg sync.WaitGroup
	for i := range retries {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			results[i], failures[i] = s.CreateTask(ctx, owner.ID, TaskInput{
				RequestKey: "parallel-task-create-001",
				ProjectID:  inbox.ID,
				Title: "One task after retries",
			})
		}(i)
	}
	wg.Wait()
	for i, err := range failures {
		if err != nil {
			t.Fatalf("retry %d: %v", i, err)
		}
		if results[i].ID != results[0].ID {
			t.Fatal("duplicate ID", results[0].ID, results[i].ID)
		}
	}
	var count int
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM tasks WHERE owner_id=$1", owner.ID).Scan(&count); err != nil || count != 1 {
		t.Fatal("duplicate task rows", count, err)
	}
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM task_create_requests WHERE owner_id=$1", owner.ID).Scan(&count); err != nil || count != 1 {
		t.Fatal("duplicate request rows", count, err)
	}

	// A failed create must not reserve its key. Repairing a bad target can
	// then succeed without accidentally claiming a prior successful write.
	_, err = s.CreateTask(ctx, owner.ID, TaskInput{
		RequestKey: "retry-after-failed-create",
		ProjectID:  "missing-project",
		Title:      "Invalid target",
	})
	if err == nil {
		t.Fatal("missing project accepted")
	}
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM task_create_requests WHERE owner_id=$1 AND request_key=$2", owner.ID, "retry-after-failed-create").Scan(&count); err != nil || count != 0 {
		t.Fatal("failed create reserved key", count, err)
	}
	if _, err := s.CreateTask(ctx, owner.ID, TaskInput{
		RequestKey: "retry-after-failed-create",
		ProjectID:  inbox.ID,
		Title: "Invalid target",
	}); err != nil {
		t.Fatal("repaired retry failed", err)
	}
	if _, err := pool.Exec(ctx, "DELETE FROM users WHERE id=$1", owner.ID); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, "SELECT count(*) FROM task_create_requests WHERE owner_id=$1", owner.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("deleted account retained task request history", count, err)
	}
}
