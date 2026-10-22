package store

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/recurrence"
)

func TestRecurringOccurrenceLifecycle(t *testing.T) {
	pool := testPool(t)
	s := New(pool)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "recurring@example.com", "hash")
	other, _ := s.CreateUser(ctx, "other-recurring@example.com", "hash")
	p, _ := s.CreateProject(ctx, u.ID, ProjectInput{Name: "Routine"})
	task, err := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Read", Due: &DueInput{Date: "2026-10-22"}})
	if err != nil {
		t.Fatal(err)
	}
	schedule := recurrence.Schedule{Start: "2026-10-22", Timezone: "Asia/Tehran", Rule: recurrence.Rule{Frequency: recurrence.Daily, Interval: 1, Calendar: recurrence.Jalali, Basis: recurrence.FromDue, Count: 2}}
	if err := s.SetTaskRecurrence(ctx, other.ID, task.ID, &schedule); !errors.Is(err, ErrTaskNotFound) {
		t.Fatal("private write", err)
	}
	if _, err := s.TaskRecurrence(ctx, other.ID, task.ID); !errors.Is(err, ErrTaskNotFound) {
		t.Fatal("private read", err)
	}
	invalid := schedule
	invalid.Timezone = "Local"
	if err := s.SetTaskRecurrence(ctx, u.ID, task.ID, &invalid); !errors.Is(err, ErrInvalidRecurrence) {
		t.Fatal("invalid zone", err)
	}
	if err := s.SetTaskRecurrence(ctx, u.ID, task.ID, &schedule); err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := s.CompleteTask(ctx, u.ID, task.ID, true)
			errs <- err
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	state, err := s.TaskRecurrence(ctx, u.ID, task.ID)
	if err != nil || state.NextTaskID == nil || state.AdvancedAt == nil {
		t.Fatal("successor missing", state, err)
	}
	firstNext := *state.NextTaskID
	list, _ := s.ListTasks(ctx, u.ID, p.ID, false)
	if len(list) != 1 || list[0].ID != firstNext {
		t.Fatal("duplicate successor", list)
	}
	if _, err := s.CompleteTask(ctx, u.ID, task.ID, false); err != nil {
		t.Fatal("undo", err)
	}
	list, _ = s.ListTasks(ctx, u.ID, p.ID, false)
	if len(list) != 1 || list[0].ID != task.ID {
		t.Fatal("undo did not restore occurrence", list)
	}
	if _, err := s.SkipRecurringTask(ctx, other.ID, task.ID); !errors.Is(err, ErrTaskNotFound) {
		t.Fatal("private skip", err)
	}
	if _, err := s.SkipRecurringTask(ctx, u.ID, task.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.SkipRecurringTask(ctx, u.ID, task.ID); err != nil {
		t.Fatal("skip retry", err)
	}
	if _, err := s.UndoRecurringTask(ctx, u.ID, task.ID); err != nil {
		t.Fatal("undo skip", err)
	}
	if _, err := s.CompleteTask(ctx, u.ID, task.ID, true); err != nil {
		t.Fatal(err)
	}
	state, _ = s.TaskRecurrence(ctx, u.ID, task.ID)
	next := *state.NextTaskID
	title := "Edited successor"
	if _, err := s.UpdateTask(ctx, u.ID, next, TaskUpdate{Title: &title}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteTask(ctx, u.ID, task.ID, false); !errors.Is(err, ErrRecurrenceConflict) {
		t.Fatal("undo discarded successor edit", err)
	}
	if _, err := s.CompleteTask(ctx, u.ID, next, true); err != nil {
		t.Fatal(err)
	}
	state, _ = s.TaskRecurrence(ctx, u.ID, next)
	if state.NextTaskID != nil || state.AdvancedAt == nil || state.Emitted != 2 {
		t.Fatal("count exhaustion", state)
	}
	var complete, skip, undo int
	if err := pool.QueryRow(ctx, `SELECT count(*) FILTER (WHERE kind='complete'),count(*) FILTER (WHERE kind='skip'),count(*) FILTER (WHERE kind='undo') FROM recurrence_events WHERE owner_id=$1`, u.ID).Scan(&complete, &skip, &undo); err != nil || complete != 3 || skip != 1 || undo != 2 {
		t.Fatal("audit history", complete, skip, undo, err)
	}
}

func TestRecurringSuccessorCanEditRuleWithoutResettingAnchor(t *testing.T) {
	pool := testPool(t)
	s := New(pool)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "recurring-anchor@example.com", "hash")
	p, _ := s.CreateProject(ctx, u.ID, ProjectInput{Name: "Routine"})
	task, err := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Read", Due: &DueInput{Date: "2000-01-01"}})
	if err != nil {
		t.Fatal(err)
	}
	schedule := recurrence.Schedule{Start: "2000-01-01", Timezone: "Asia/Tehran", Rule: recurrence.Rule{Frequency: recurrence.Daily, Interval: 1, Calendar: recurrence.Jalali, Basis: recurrence.FromDue}}
	if err := s.SetTaskRecurrence(ctx, u.ID, task.ID, &schedule); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteTask(ctx, u.ID, task.ID, true); err != nil {
		t.Fatal(err)
	}
	state, err := s.TaskRecurrence(ctx, u.ID, task.ID)
	if err != nil || state == nil || state.NextTaskID == nil {
		t.Fatal("missing successor", state, err)
	}
	next := *state.NextTaskID
	schedule.Rule.Interval = 3
	if err := s.SetTaskRecurrence(ctx, u.ID, next, &schedule); err != nil {
		t.Fatal("successor rule edit rejected", err)
	}
	saved, err := s.TaskRecurrence(ctx, u.ID, next)
	if err != nil || saved.Schedule.Start != "2000-01-01" || saved.Emitted != 2 || saved.Schedule.Rule.Interval != 3 {
		t.Fatal("series anchor/count changed", saved, err)
	}
	schedule.Start = "2000-01-02"
	if err := s.SetTaskRecurrence(ctx, u.ID, next, &schedule); !errors.Is(err, ErrInvalidRecurrence) {
		t.Fatal("anchor mutation accepted", err)
	}
}

func TestRecurringUndoPreservesSuccessorScrumEdits(t *testing.T) {
	pool := testPool(t)
	s := New(pool)
	ctx := context.Background()
	u, err := s.CreateUser(ctx, "recurring-scrum@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	p, err := s.CreateProject(ctx, u.ID, ProjectInput{Name: "Routine"})
	if err != nil {
		t.Fatal(err)
	}
	task, err := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Read", Due: &DueInput{Date: "2026-10-22"}})
	if err != nil {
		t.Fatal(err)
	}
	schedule := recurrence.Schedule{Start: "2026-10-22", Timezone: "Asia/Tehran", Rule: recurrence.Rule{Frequency: recurrence.Daily, Interval: 1, Calendar: recurrence.Jalali, Basis: recurrence.FromDue}}
	if err := s.SetTaskRecurrence(ctx, u.ID, task.ID, &schedule); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteTask(ctx, u.ID, task.ID, true); err != nil {
		t.Fatal(err)
	}
	state, err := s.TaskRecurrence(ctx, u.ID, task.ID)
	if err != nil || state.NextTaskID == nil {
		t.Fatal(state, err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO scrum_items(task_id,owner_id,issue_type,stage) VALUES($1,$2,'story','todo')`, *state.NextTaskID, u.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UndoRecurringTask(ctx, u.ID, task.ID); !errors.Is(err, ErrRecurrenceConflict) {
		t.Fatal("undo discarded Scrum metadata", err)
	}
	var preserved bool
	if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM scrum_items WHERE task_id=$1 AND owner_id=$2)`, *state.NextTaskID, u.ID).Scan(&preserved); err != nil || !preserved {
		t.Fatal("successor removed", err)
	}
}
