package store

import (
	"context"
	"errors"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/recurrence"
)

func TestRecurringUndoCannotDiscardSuccessorComment(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	u, err := s.CreateUser(ctx, "recurring-comments@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	p, err := s.CreateProject(ctx, u.ID, ProjectInput{Name: "Routine"})
	if err != nil {
		t.Fatal(err)
	}
	task, err := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Read", Due: &DueInput{Date: "2000-01-01"}})
	if err != nil {
		t.Fatal(err)
	}
	rule := recurrence.Schedule{Start: "2000-01-01", Timezone: "Asia/Tehran", Rule: recurrence.Rule{Frequency: recurrence.Daily, Interval: 1, Calendar: recurrence.Jalali, Basis: recurrence.FromDue}}
	if err := s.SetTaskRecurrence(ctx, u.ID, task.ID, &rule); err != nil {
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
	comment, err := s.WriteComment(ctx, u.ID, "task", next, "create", "", CommentInput{Body: "Keep my reading notes", RequestKey: "reading-notes-123"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.CompleteTask(ctx, u.ID, task.ID, false); !errors.Is(err, ErrRecurrenceConflict) {
		t.Fatal("undo could delete successor history", err)
	}
	page, err := s.ListComments(ctx, u.ID, "task", next, "")
	if err != nil || len(page.Comments) != 1 || page.Comments[0].ID != comment.ID {
		t.Fatal("successor comment was lost", page, err)
	}
}
