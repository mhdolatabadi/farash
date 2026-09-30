package store

import (
	"context"
	"errors"
	"testing"
)

func newOwner(t *testing.T, s *Store, email string) string {
	t.Helper()
	user, err := s.CreateUser(context.Background(), email, "hash")
	if err != nil {
		t.Fatal(err)
	}
	return user.ID
}

func mustCreate(t *testing.T, s *Store, owner, name string, parent *string) Project {
	t.Helper()
	p, err := s.CreateProject(context.Background(), owner, NewProject{Name: name, Color: "blue", ParentID: parent})
	if err != nil {
		t.Fatalf("create %q: %v", name, err)
	}
	return p
}

func names(projects []Project) []string {
	out := make([]string, len(projects))
	for i, p := range projects {
		out[i] = p.Name
	}
	return out
}

func equal(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestRegisteringCreatesOneInbox(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner := newOwner(t, s, "a@example.com")

	projects, err := s.Projects(ctx, owner, false)
	if err != nil {
		t.Fatal(err)
	}
	if len(projects) != 1 || !projects[0].IsInbox || projects[0].Name != InboxName {
		t.Fatalf("projects = %+v", projects)
	}

	// A second Inbox for the same account is refused by the database.
	if _, err := s.pool.Exec(ctx,
		`INSERT INTO projects (id, owner_id, name, is_inbox) VALUES ('x', $1, 'Inbox', true)`, owner); err == nil {
		t.Fatal("second inbox was accepted")
	}
}

func TestProjectsAreOrderedAndOwnerScoped(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	alice := newOwner(t, s, "alice@example.com")
	bob := newOwner(t, s, "bob@example.com")

	work := mustCreate(t, s, alice, "Work", nil)
	home := mustCreate(t, s, alice, "Home", nil)
	mustCreate(t, s, bob, "Bob's", nil)

	projects, err := s.Projects(ctx, alice, false)
	if err != nil {
		t.Fatal(err)
	}
	if got := names(projects); !equal(got, []string{InboxName, "Work", "Home"}) {
		t.Fatalf("names = %v", got)
	}

	if err := s.ReorderProjects(ctx, alice, []string{home.ID, work.ID}); err != nil {
		t.Fatal(err)
	}
	projects, _ = s.Projects(ctx, alice, false)
	if got := names(projects); !equal(got, []string{InboxName, "Home", "Work"}) {
		t.Fatalf("after reorder = %v", got)
	}

	if _, err := s.Project(ctx, bob, work.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob reading alice's project: %v", err)
	}
	if _, err := s.UpdateProject(ctx, bob, work.ID, ProjectChanges{Name: ptr("x")}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob renaming alice's project: %v", err)
	}
	if err := s.DeleteProject(ctx, bob, work.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob deleting alice's project: %v", err)
	}
	if err := s.ReorderProjects(ctx, bob, []string{work.ID}); !errors.Is(err, ErrNotFound) {
		t.Fatalf("bob reordering alice's project: %v", err)
	}
	if _, err := s.CreateProject(ctx, bob, NewProject{Name: "x", Color: "blue", ParentID: &work.ID}); !errors.Is(err, ErrInvalidParent) {
		t.Fatalf("bob nesting under alice's project: %v", err)
	}
}

func TestReorderNeedsSiblings(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner := newOwner(t, s, "a@example.com")
	parent := mustCreate(t, s, owner, "Parent", nil)
	child := mustCreate(t, s, owner, "Child", &parent.ID)

	if err := s.ReorderProjects(ctx, owner, []string{parent.ID, child.ID}); !errors.Is(err, ErrInvalidOrder) {
		t.Fatalf("mixed parents: %v", err)
	}
	if err := s.ReorderProjects(ctx, owner, []string{parent.ID, parent.ID}); !errors.Is(err, ErrInvalidOrder) {
		t.Fatalf("duplicate ids: %v", err)
	}
}

func TestInboxIsProtected(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner := newOwner(t, s, "a@example.com")
	projects, _ := s.Projects(ctx, owner, false)
	inbox := projects[0]
	other := mustCreate(t, s, owner, "Other", nil)

	for name, changes := range map[string]ProjectChanges{
		"rename":  {Name: ptr("Mine")},
		"archive": {IsArchived: ptr(true)},
		"move":    {MoveParent: true, ParentID: &other.ID},
	} {
		if _, err := s.UpdateProject(ctx, owner, inbox.ID, changes); !errors.Is(err, ErrInboxProtected) {
			t.Fatalf("%s: %v", name, err)
		}
	}
	if err := s.DeleteProject(ctx, owner, inbox.ID); !errors.Is(err, ErrInboxProtected) {
		t.Fatalf("delete: %v", err)
	}
	if _, err := s.CreateProject(ctx, owner, NewProject{Name: "x", Color: "blue", ParentID: &inbox.ID}); !errors.Is(err, ErrInvalidParent) {
		t.Fatalf("child of inbox: %v", err)
	}

	// Color and favourite are fine.
	updated, err := s.UpdateProject(ctx, owner, inbox.ID, ProjectChanges{Color: ptr("red"), IsFavorite: ptr(true)})
	if err != nil || updated.Color != "red" || !updated.IsFavorite {
		t.Fatalf("update = %+v, %v", updated, err)
	}
}

func TestNestingDepthAndCycles(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner := newOwner(t, s, "a@example.com")

	l1 := mustCreate(t, s, owner, "L1", nil)
	l2 := mustCreate(t, s, owner, "L2", &l1.ID)
	l3 := mustCreate(t, s, owner, "L3", &l2.ID)
	l4 := mustCreate(t, s, owner, "L4", &l3.ID)
	if _, err := s.CreateProject(ctx, owner, NewProject{Name: "L5", Color: "blue", ParentID: &l4.ID}); !errors.Is(err, ErrInvalidParent) {
		t.Fatalf("fifth level: %v", err)
	}

	// Moving L1 under its own descendant would make a cycle.
	if _, err := s.UpdateProject(ctx, owner, l1.ID, ProjectChanges{MoveParent: true, ParentID: &l3.ID}); !errors.Is(err, ErrInvalidParent) {
		t.Fatalf("cycle: %v", err)
	}
	if _, err := s.UpdateProject(ctx, owner, l1.ID, ProjectChanges{MoveParent: true, ParentID: &l1.ID}); !errors.Is(err, ErrInvalidParent) {
		t.Fatalf("self parent: %v", err)
	}

	// A two-level subtree fits under L2 (levels 3 and 4) but not under L3.
	other := mustCreate(t, s, owner, "Other", nil)
	mustCreate(t, s, owner, "Other child", &other.ID)
	if _, err := s.UpdateProject(ctx, owner, other.ID, ProjectChanges{MoveParent: true, ParentID: &l3.ID}); !errors.Is(err, ErrInvalidParent) {
		t.Fatalf("too deep move: %v", err)
	}
	moved, err := s.UpdateProject(ctx, owner, other.ID, ProjectChanges{MoveParent: true, ParentID: &l2.ID})
	if err != nil || moved.ParentID == nil || *moved.ParentID != l2.ID {
		t.Fatalf("move = %+v, %v", moved, err)
	}

	// And back to the top level.
	moved, err = s.UpdateProject(ctx, owner, other.ID, ProjectChanges{MoveParent: true})
	if err != nil || moved.ParentID != nil {
		t.Fatalf("move to top = %+v, %v", moved, err)
	}
}

func TestArchiveCascadesAndRestoresAncestors(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner := newOwner(t, s, "a@example.com")
	parent := mustCreate(t, s, owner, "Parent", nil)
	child := mustCreate(t, s, owner, "Child", &parent.ID)

	if _, err := s.UpdateProject(ctx, owner, parent.ID, ProjectChanges{IsArchived: ptr(true)}); err != nil {
		t.Fatal(err)
	}
	archived, _ := s.Projects(ctx, owner, true)
	if got := names(archived); !equal(got, []string{"Parent", "Child"}) {
		t.Fatalf("archived = %v", got)
	}
	if _, err := s.CreateProject(ctx, owner, NewProject{Name: "x", Color: "blue", ParentID: &parent.ID}); !errors.Is(err, ErrInvalidParent) {
		t.Fatalf("child of archived project: %v", err)
	}

	// Restoring the child brings its parent back too.
	if _, err := s.UpdateProject(ctx, owner, child.ID, ProjectChanges{IsArchived: ptr(false)}); err != nil {
		t.Fatal(err)
	}
	active, _ := s.Projects(ctx, owner, false)
	if got := names(active); !equal(got, []string{InboxName, "Parent", "Child"}) {
		t.Fatalf("active = %v", got)
	}
}

func TestDeleteRemovesSubprojects(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner := newOwner(t, s, "a@example.com")
	parent := mustCreate(t, s, owner, "Parent", nil)
	child := mustCreate(t, s, owner, "Child", &parent.ID)

	if err := s.DeleteProject(ctx, owner, parent.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Project(ctx, owner, child.ID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("child after delete: %v", err)
	}
}

func ptr[T any](v T) *T { return &v }
