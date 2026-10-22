package store

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"
)

func TestCommentCreateInvalidatesTaskVersionButRetryDoesNot(t *testing.T) {
	pool := testPool(t)
	s := New(pool)
	ctx := context.Background()
	u, err := s.CreateUser(ctx, "comment-version@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	p, err := s.CreateProject(ctx, u.ID, ProjectInput{Name: "Notes"})
	if err != nil {
		t.Fatal(err)
	}
	task, err := s.CreateTask(ctx, u.ID, TaskInput{ProjectID: p.ID, Title: "Read"})
	if err != nil {
		t.Fatal(err)
	}
	in := CommentInput{Body: "Keep these notes", RequestKey: "version-test-123"}
	if _, err := s.WriteComment(ctx, u.ID, "task", task.ID, "create", "", in); err != nil {
		t.Fatal(err)
	}
	var changed, retried time.Time
	if err := pool.QueryRow(ctx, `SELECT updated_at FROM tasks WHERE id=$1`, task.ID).Scan(&changed); err != nil || !changed.After(task.UpdatedAt) {
		t.Fatal("comment did not invalidate task version", changed, task.UpdatedAt, err)
	}
	if _, err := s.WriteComment(ctx, u.ID, "task", task.ID, "create", "", in); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx, `SELECT updated_at FROM tasks WHERE id=$1`, task.ID).Scan(&retried); err != nil || !retried.Equal(changed) {
		t.Fatal("create retry changed task version", retried, changed, err)
	}
}

func TestCommentsHistoryPrivacyAndIdempotency(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner, err := s.CreateUser(ctx, "comments-owner@example.com", "unused")
	if err != nil {
		t.Fatal(err)
	}
	other, err := s.CreateUser(ctx, "comments-other@example.com", "unused")
	if err != nil {
		t.Fatal(err)
	}
	project, err := s.CreateProject(ctx, owner.ID, ProjectInput{Name: "Comments"})
	if err != nil {
		t.Fatal(err)
	}
	task, err := s.CreateTask(ctx, owner.ID, TaskInput{ProjectID: project.ID, Title: "Private task"})
	if err != nil {
		t.Fatal(err)
	}
	for _, target := range []struct{ kind, id string }{{"project", project.ID}, {"task", task.ID}} {
		if _, err := s.ListComments(ctx, other.ID, target.kind, target.id, ""); !errors.Is(err, ErrCommentNotFound) {
			t.Fatal("private read", err)
		}
		if _, err := s.WriteComment(ctx, other.ID, target.kind, target.id, "create", "", CommentInput{Body: "secret", RequestKey: "private-123"}); !errors.Is(err, ErrCommentNotFound) {
			t.Fatal("private write", err)
		}
	}
	input := CommentInput{Body: "  متن **یادداشت**  ", RequestKey: "original-request"}
	first, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "create", "", input)
	if err != nil {
		t.Fatal(err)
	}
	if first.Body != "متن **یادداشت**" {
		t.Fatal(first)
	}
	duplicate, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "create", "", input)
	if err != nil || duplicate.ID != first.ID {
		t.Fatal("retry duplicated", duplicate, err)
	}
	if _, err := s.WriteComment(ctx, owner.ID, "project", project.ID, "create", "", input); !errors.Is(err, ErrCommentConflict) {
		t.Fatal("reused key across targets", err)
	}
	if _, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "create", "", CommentInput{Body: "changed payload", RequestKey: input.RequestKey}); !errors.Is(err, ErrCommentConflict) {
		t.Fatal("changed retry", err)
	}
	edited, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "edit", first.ID, CommentInput{Body: "ویرایش"})
	if err != nil || edited.Body != "ویرایش" {
		t.Fatal(edited, err)
	}
	duplicate, err = s.WriteComment(ctx, owner.ID, "task", task.ID, "create", "", input)
	if err != nil || duplicate.Body != edited.Body {
		t.Fatal("create retry reverted edit", duplicate, err)
	}
	for _, body := range []string{" ", strings.Repeat("الف", 16001)} {
		if _, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "edit", first.ID, CommentInput{Body: body}); !errors.Is(err, ErrCommentInvalid) {
			t.Fatal("invalid text", err)
		}
	}
	if _, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "create", "", CommentInput{Body: "text", RequestKey: "bad"}); !errors.Is(err, ErrCommentInvalid) {
		t.Fatal("invalid key", err)
	}
	removed, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "delete", first.ID, CommentInput{})
	if err != nil || removed.Body != "" || removed.DeletedAt == nil {
		t.Fatal(removed, err)
	}
	retry, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "delete", first.ID, CommentInput{})
	if err != nil || !retry.UpdatedAt.Equal(removed.UpdatedAt) {
		t.Fatal("delete retry", retry, err)
	}
	duplicate, err = s.WriteComment(ctx, owner.ID, "task", task.ID, "create", "", input)
	if err != nil || duplicate.DeletedAt == nil {
		t.Fatal("create retry resurrected deleted comment", duplicate, err)
	}
	if _, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "edit", first.ID, CommentInput{Body: "resurrect"}); !errors.Is(err, ErrCommentNotFound) {
		t.Fatal("edited deleted comment", err)
	}
	page, err := s.ListComments(ctx, owner.ID, "task", task.ID, "")
	if err != nil || page.Total != 0 || len(page.Comments) != 1 || page.Comments[0].Body != "" {
		t.Fatal("tombstone", page, err)
	}
	if _, err := s.WriteComment(ctx, owner.ID, "project", project.ID, "edit", first.ID, CommentInput{Body: "cross-target"}); !errors.Is(err, ErrCommentNotFound) {
		t.Fatal("cross-target edit", err)
	}
	if err := s.DeleteTask(ctx, owner.ID, task.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ListComments(ctx, owner.ID, "task", task.ID, ""); !errors.Is(err, ErrCommentNotFound) {
		t.Fatal("deleted target readable", err)
	}
	if _, err := s.RestoreTask(ctx, owner.ID, task.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ListComments(ctx, owner.ID, "task", task.ID, ""); err != nil {
		t.Fatal("restored target loses history", err)
	}
	if _, err := s.pool.Exec(ctx, "UPDATE projects SET is_archived=true WHERE id=$1", project.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ListComments(ctx, owner.ID, "task", task.ID, ""); err != nil {
		t.Fatal("archive read", err)
	}
	if _, err := s.WriteComment(ctx, owner.ID, "task", task.ID, "create", "", CommentInput{Body: "archived", RequestKey: "archived-request"}); !errors.Is(err, ErrCommentConflict) {
		t.Fatal("archive write", err)
	}
	if err := s.DeleteProject(ctx, owner.ID, project.ID); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := s.pool.QueryRow(ctx, "SELECT count(*) FROM comments WHERE owner_id=$1", owner.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("cascade", count, err)
	}
}

func TestCommentsPaginationAndConcurrentRetry(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner, err := s.CreateUser(ctx, "comments-page@example.com", "unused")
	if err != nil {
		t.Fatal(err)
	}
	project, err := s.CreateProject(ctx, owner.ID, ProjectInput{Name: "Pages"})
	if err != nil {
		t.Fatal(err)
	}
	in := CommentInput{Body: "same intent", RequestKey: "concurrent-intent"}
	start := make(chan struct{})
	results := make(chan Comment, 2)
	failures := make(chan error, 2)
	var workers sync.WaitGroup
	for i := 0; i < 2; i++ {
		workers.Add(1)
		go func() {
			defer workers.Done()
			<-start
			c, e := s.WriteComment(ctx, owner.ID, "project", project.ID, "create", "", in)
			results <- c
			failures <- e
		}()
	}
	close(start)
	workers.Wait()
	close(failures)
	for err := range failures {
		if err != nil {
			t.Fatal(err)
		}
	}
	a, b := <-results, <-results
	if a.ID != b.ID {
		t.Fatal("concurrent retry duplicated", a, b)
	}
	for i := 0; i < 51; i++ {
		if _, err := s.WriteComment(ctx, owner.ID, "project", project.ID, "create", "", CommentInput{Body: fmt.Sprint(i), RequestKey: fmt.Sprintf("comment-%03d", i)}); err != nil {
			t.Fatal(err)
		}
	}
	first, err := s.ListComments(ctx, owner.ID, "project", project.ID, "")
	if err != nil || first.Total != 52 || len(first.Comments) != 50 || first.Next == "" {
		t.Fatal(first, err)
	}
	// A deleted cursor remains a usable content-free page anchor.
	if _, err := s.WriteComment(ctx, owner.ID, "project", project.ID, "delete", first.Next, CommentInput{}); err != nil {
		t.Fatal(err)
	}
	second, err := s.ListComments(ctx, owner.ID, "project", project.ID, first.Next)
	if err != nil || len(second.Comments) != 2 || second.Next != "" || second.Total != 51 {
		t.Fatal(second, err)
	}
	if _, err := s.ListComments(ctx, owner.ID, "project", project.ID, "private-cursor"); !errors.Is(err, ErrCommentInvalid) {
		t.Fatal("invalid cursor", err)
	}
	if _, err := s.pool.Exec(ctx, `INSERT INTO comments(id,owner_id,project_id,body,request_key,request_hash)
 SELECT 'bulk-comment-'||n,$1,$2,'bounded','bulk-request-'||n,'unused' FROM generate_series(1,4948) n`, owner.ID, project.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.WriteComment(ctx, owner.ID, "project", project.ID, "create", "", CommentInput{Body: "over quota", RequestKey: "quota-overflow"}); !errors.Is(err, ErrCommentConflict) {
		t.Fatal("target quota", err)
	}
}
