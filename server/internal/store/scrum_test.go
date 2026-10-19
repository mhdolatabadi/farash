package store

import (
	"context"
	"errors"
	"sync"
	"testing"
	"time"
)

func TestSprintValidation(t *testing.T) {
	in := AgileCommand{Name: "one", StartsOn: "2026-01-01", EndsOn: "2026-01-15"}
	if !validSprint(in) {
		t.Fatal("valid")
	}
	in.EndsOn = "2026-12-01"
	if validSprint(in) {
		t.Fatal("unbounded")
	}
	in.EndsOn = "2026-01-15"
	in.Name = " "
	if validSprint(in) {
		t.Fatal("name")
	}
}
func TestPersonalScrumLifecycle(t *testing.T) {
	pool := testPool(t)
	s := New(pool)
	ctx := context.Background()
	u, _ := s.CreateUser(ctx, "scrum@example.com", "hash")
	other, _ := s.CreateUser(ctx, "outsider@example.com", "hash")
	p, e := s.CreateProject(ctx, u.ID, ProjectInput{Name: "Personal"})
	if e != nil {
		t.Fatal(e)
	}
	w := func(action, id string, in AgileCommand) {
		t.Helper()
		if e := s.AgileWrite(ctx, u.ID, p.ID, action, id, in); e != nil {
			t.Fatal(action, e)
		}
	}
	get := func() AgileWorkspace {
		t.Helper()
		r, e := s.AgileWorkspace(ctx, u.ID, p.ID)
		if e != nil {
			t.Fatal(e)
		}
		return r
	}
	if get().Method != "simple" {
		t.Fatal("default")
	}
	w("method", "", AgileCommand{Method: "scrum"})
	if _, e = s.AgileWorkspace(ctx, other.ID, p.ID); !errors.Is(e, ErrAgileNotFound) {
		t.Fatal("privacy", e)
	}
	a, _ := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Story"})
	b, _ := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Bug"})
	plan := AgileCommand{Name: "Sprint", Goal: "Deliver one", StartsOn: "2026-01-01", EndsOn: "2026-01-14", RequestKey: "sprint-create-key"}
	w("create", "", plan)
	w("create", "", plan)
	if len(get().Sprints) != 1 {
		t.Fatal("retry duplicates")
	}
	sid := get().Sprints[0].ID
	points := 3
	item := AgileCommand{SprintID: &sid, IssueType: "story", Stage: "todo", Points: &points, Acceptance: "Works"}
	w("item", a.ID, item)
	item.IssueType = "bug"
	w("item", b.ID, item)
	plan.RequestKey = "second-sprint-key"
	plan.Name = "Next"
	w("create", "", plan)
	next := get().Sprints[0].ID
	// Both devices start different planned sprints, exactly one wins.
	// The second needs scope too; keep first source and add a third task.
	c, _ := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Other"})
	item.SprintID = &next
	w("item", c.ID, item)
	var wg sync.WaitGroup
	results := make(chan error, 2)
	for _, id := range []string{sid, next} {
		wg.Add(1)
		go func(id string) {
			defer wg.Done()
			results <- s.AgileWrite(ctx, u.ID, p.ID, "start", id, AgileCommand{})
		}(id)
	}
	wg.Wait()
	close(results)
	success, conflict := 0, 0
	for err := range results {
		if err == nil {
			success++
		} else if errors.Is(err, ErrAgileConflict) {
			conflict++
		} else {
			t.Fatal(err)
		}
	}
	if success != 1 || conflict != 1 {
		t.Fatal(success, conflict)
	}
	active := ""
	for _, sp := range get().Sprints {
		if sp.State == "active" {
			active = sp.ID
		}
	}
	if active == next {
		w("close", next, AgileCommand{})
		w("start", sid, AgileCommand{})
	}
	if e = s.AgileWrite(ctx, u.ID, p.ID, "method", "", AgileCommand{Method: "simple"}); !errors.Is(e, ErrAgileConflict) {
		t.Fatal("hidden active", e)
	}
	item.SprintID = &sid
	points = 8
	if e = s.AgileWrite(ctx, u.ID, p.ID, "item", a.ID, item); !errors.Is(e, ErrAgileConflict) {
		t.Fatal("reestimate active", e)
	}
	points = 3
	// Time is measured in actual execution bounds, then frozen on closure.
	pool.Exec(ctx, `UPDATE sprints SET started_at=now()-interval '2 minutes' WHERE id=$1`, sid)
	now := time.Now()
	timeStart, timeEnd := now.Add(-90*time.Second), now.Add(-30*time.Second)
	recorded, err := s.CreateTime(ctx, u.ID, TimeInput{TaskID: a.ID, Source: "manual", RequestKey: "scrum-time-key", Started: timeStart, Ended: &timeEnd})
	if err != nil {
		t.Fatal(err)
	}
	s.CompleteTask(ctx, u.ID, a.ID, true)
	item.Acceptance = "Can refine acceptance after completing"
	w("item", a.ID, item)
	before := get()
	var sprint Sprint
	for _, sp := range before.Sprints {
		if sp.ID == sid {
			sprint = sp
		}
	}
	if sprint.DonePoints != 3 || sprint.CommittedPoints != 6 || sprint.DoneCount != 1 {
		t.Fatalf("totals %+v", sprint)
	}
	w("close", sid, AgileCommand{Review: "One delivered", Retro: "Smaller scope"})
	w("close", sid, AgileCommand{Review: "must not overwrite"})
	s.DeleteTime(ctx, u.ID, recorded.ID)
	s.CompleteTask(ctx, u.ID, a.ID, false)
	s.DeleteTask(ctx, u.ID, a.ID)
	after := get()
	for _, sp := range after.Sprints {
		if sp.ID == sid && (sp.DonePoints != 3 || sp.DoneCount != 1 || sp.Review != "One delivered" || sp.TrackedSeconds != 60) {
			t.Fatalf("history changed %+v", sp)
		}
	}
	for _, it := range after.Items {
		if it.Task.ID == b.ID && it.SprintID != nil {
			t.Fatal("unfinished not returned")
		}
	}
	if len(after.Events) < 3 {
		t.Fatal("burndown events")
	}
	w("notes", sid, AgileCommand{Review: "Updated review", Retro: "Next action"})
	for _, sp := range get().Sprints {
		if sp.ID == sid && (sp.Review != "Updated review" || sp.DonePoints != 3 || sp.TrackedSeconds != 60) {
			t.Fatal("notes changed measured history", sp)
		}
	}

	w("method", "", AgileCommand{Method: "kanban"})
	if len(get().Sprints) != 2 {
		t.Fatal("history lost on method change")
	}
	// Deleting or moving active scope updates remaining scope without erasing commitment.
	plan.RequestKey = "third-sprint-key"
	plan.Name = "Third"
	w("method", "", AgileCommand{Method: "scrum"})
	w("create", "", plan)
	third := get().Sprints[0].ID
	item.SprintID = &third
	w("item", b.ID, item)
	already, _ := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Already delivered"})
	w("item", already.ID, item)
	s.CompleteTask(ctx, u.ID, already.ID, true)
	w("start", third, AgileCommand{})
	for _, it := range get().Items {
		if it.Task.ID == already.ID && it.SprintID != nil {
			t.Fatal("pre-completed work entered scope")
		}
	}
	s.DeleteTask(ctx, u.ID, b.ID)
	for _, sp := range get().Sprints {
		if sp.ID == third && (sp.ScopeCount != 0 || sp.CommittedCount != 1) {
			t.Fatalf("deleted scope %+v", sp)
		}
	}
}
