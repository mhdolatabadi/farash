package store

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

func TestTimeIntervals(t *testing.T) {
	now := time.Now()
	valid := now.Add(-time.Minute)
	end := now
	future := now.Add(time.Hour)
	if !validInterval(valid, &end, now) || validInterval(now, &end, now) || validInterval(valid, &future, now) || validInterval(now.Add(-25*time.Hour), &end, now) {
		t.Fatal("interval validation")
	}
}
func TestDurableTimeAccounting(t *testing.T) {
	pool := testPool(t)
	s := New(pool)
	ctx := context.Background()
	owner, _ := s.CreateUser(ctx, "time@example.com", "hash")
	other, _ := s.CreateUser(ctx, "other-time@example.com", "hash")
	project, _ := s.EnsureInboxProject(ctx, owner.ID)
	task, err := s.CreateTask(ctx, owner.ID, TaskInput{ProjectID: project.ID, Title: "work", Priority: 4})
	if err != nil {
		t.Fatal(err)
	}
	in := TimeInput{TaskID: task.ID, Source: "timer", RequestKey: "first-start-key"}
	first, err := s.CreateTime(ctx, owner.ID, in)
	if err != nil {
		t.Fatal(err)
	}
	retry, err := s.CreateTime(ctx, owner.ID, in)
	if err != nil || retry.ID != first.ID {
		t.Fatalf("retry %+v %v", retry, err)
	}
	if _, err = s.StopTime(ctx, other.ID, first.ID); !errors.Is(err, ErrTimeNotFound) {
		t.Fatal("private stop", err)
	}
	if _, err = s.CreateTime(ctx, other.ID, TimeInput{TaskID: task.ID, Source: "timer", RequestKey: "private-task-key"}); !errors.Is(err, ErrTaskNotFound) {
		t.Fatal("private start", err)
	}
	stopped, err := s.StopTime(ctx, owner.ID, first.ID)
	if err != nil || stopped.Ended == nil {
		t.Fatal("stop", err)
	}
	again, _ := s.StopTime(ctx, owner.ID, first.ID)
	if !again.Ended.Equal(*stopped.Ended) {
		t.Fatal("stop not idempotent")
	}
	// A retry after the session has ended must not start a new interval.
	same, err := s.CreateTime(ctx, owner.ID, in)
	if err != nil || same.Ended == nil {
		t.Fatal("late retry restarted", err)
	}
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for _, key := range []string{"concurrent-key-one", "concurrent-key-two"} {
		wg.Add(1)
		go func(key string) {
			defer wg.Done()
			_, err := s.CreateTime(ctx, owner.ID, TimeInput{TaskID: task.ID, Source: "timer", RequestKey: key})
			results <- err
		}(key)
	}
	wg.Wait()
	close(results)
	success, conflict := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else if errors.Is(err, ErrTimerRunning) {
			conflict++
		} else {
			t.Fatal(err)
		}
	}
	if success != 1 || conflict != 1 {
		t.Fatalf("concurrent starts %d %d", success, conflict)
	}
	zone, _ := time.LoadLocation("Asia/Tehran")
	from, to := ProgressWeek(time.Now(), zone)
	r, err := s.TimeReport(ctx, owner.ID, from, to, zone, "")
	if err != nil || r.Active == nil {
		t.Fatal("active", err)
	}
	active := r.Active
	s.StopTime(ctx, owner.ID, first.ID)
	r, _ = s.TimeReport(ctx, owner.ID, from, to, zone, "")
	if r.Active == nil || r.Active.ID != active.ID {
		t.Fatal("stale stop stopped new entry")
	}
	if _, err = s.CompleteTask(ctx, owner.ID, task.ID, true); err != nil {
		t.Fatal(err)
	}
	r, _ = s.TimeReport(ctx, owner.ID, from, to, zone, "")
	if r.Active != nil {
		t.Fatal("completion failed to stop timer")
	}
	// Precise overlap clipping across a local midnight and manual correction.
	pool.Exec(ctx, `DELETE FROM time_entries WHERE owner_id=$1`, owner.ID)
	now := time.Now().In(zone)
	midnight := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, zone)
	start, end := midnight.Add(-30*time.Minute), midnight.Add(-10*time.Minute)
	e, err := s.CreateTime(ctx, owner.ID, TimeInput{TaskID: task.ID, Source: "manual", RequestKey: "manual-time-key", Started: start, Ended: &end})
	if err != nil {
		t.Fatal(err)
	}
	r, err = s.TimeReport(ctx, owner.ID, start.Add(-time.Hour), midnight, zone, "")
	if err != nil || r.Seconds != 1200 || r.TodaySeconds != 0 || len(r.Tasks) != 1 || r.Tasks[0].ProjectID == nil || *r.Tasks[0].ProjectID != task.ProjectID {
		t.Fatalf("manual totals %+v %v", r, err)
	}
	cutoff := start.Add(5 * time.Minute)
	r, err = s.TimeReport(ctx, owner.ID, start.Add(-time.Hour), cutoff, zone, "")
	if err != nil || r.Seconds != 300 {
		t.Fatalf("boundary clipping %+v %v", r, err)
	}
	if _, err = s.EditTime(ctx, other.ID, e.ID, TimeInput{Started: start, Ended: &end}); !errors.Is(err, ErrTimeNotFound) {
		t.Fatal("private edit", err)
	}
	end = start.Add(10 * time.Minute)
	if _, err = s.EditTime(ctx, owner.ID, e.ID, TimeInput{Started: start, Ended: &end}); err != nil {
		t.Fatal(err)
	}
	if err = s.DeleteTime(ctx, other.ID, e.ID); !errors.Is(err, ErrTimeNotFound) {
		t.Fatal("private delete", err)
	}
	s.DeleteTime(ctx, owner.ID, e.ID)
	focus, err := s.CreateTime(ctx, owner.ID, TimeInput{TaskID: task.ID, Source: "focus", FocusSeconds: 1, RequestKey: "focus-time-key"})
	if err != nil {
		t.Fatal(err)
	}
	// Model a suspended client: expiry is accounted on the server, no client tick needed.
	pool.Exec(ctx, `UPDATE time_entries SET started_at=now()-interval '2 minutes',planned_end=now()-interval '1 minute' WHERE id=$1`, focus.ID)
	retried, err := s.CreateTime(ctx, owner.ID, TimeInput{TaskID: task.ID, Source: "focus", FocusSeconds: 1, RequestKey: "focus-time-key"})
	if err != nil || retried.Ended == nil {
		t.Fatal("expired focus retry", err)
	}
	r, err = s.TimeReport(ctx, owner.ID, from, to, zone, "")
	if err != nil || r.Active != nil || r.Seconds != 60 {
		t.Fatalf("focus expiry %+v %v", r, err)
	}
	private, _ := s.TimeReport(ctx, other.ID, from, to, zone, "")
	if len(private.Entries) != 0 || private.Seconds != 0 {
		t.Fatal("report leaked")
	}
}
