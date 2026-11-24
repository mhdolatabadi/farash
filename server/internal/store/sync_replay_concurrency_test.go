package store

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

// A mobile client may retry a timed-out create while the original request is
// still running. Both responses must refer to one committed task.
func TestConcurrentOfflineCreateReplayIsIdempotent(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	s := New(testPool(t))
	user, err := s.CreateUser(ctx, "sync-replay-race@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.EnsureInboxProject(ctx, user.ID); err != nil {
		t.Fatal(err)
	}
	input := TaskInput{Title: "Created offline", RequestKey: "offline-create-0001"}
	const workers = 8
	results := make([]Task, workers)
	failures := make([]error, workers)
	var wg sync.WaitGroup
	start := make(chan struct{})
	for i := range results {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			<-start
			results[i], failures[i] = s.CreateTask(ctx, user.ID, input)
		}(i)
	}
	close(start)
	wg.Wait()
	for i := range results {
		if failures[i] != nil {
			t.Fatalf("worker %d: %v", i, failures[i])
		}
		if results[i].ID != results[0].ID {
			t.Fatalf("replay created a different task: %s vs %s", results[i].ID, results[0].ID)
		}
	}
	var count int
	if err := s.pool.QueryRow(ctx, "SELECT count(*) FROM tasks WHERE owner_id=$1 AND title=$2", user.ID, input.Title).Scan(&count); err != nil || count != 1 {
		t.Fatalf("expected one committed task, got %d: %v", count, err)
	}
	if _, err := s.CreateTask(ctx, user.ID, TaskInput{Title: "Different payload", RequestKey: input.RequestKey}); !errors.Is(err, ErrTaskRequestConflict) {
		t.Fatalf("same key with different payload must conflict: %v", err)
	}
}
