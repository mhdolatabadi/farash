package store

import (
	"context"
	"errors"
	"testing"
)

func TestCollaborationLifecycleAndIsolation(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner, err := s.CreateUser(ctx, "collab-owner@example.com", "unused")
	if err != nil {
		t.Fatal(err)
	}
	member, err := s.CreateUser(ctx, "collab-member@example.com", "unused")
	if err != nil {
		t.Fatal(err)
	}
	outsider, err := s.CreateUser(ctx, "collab-other@example.com", "unused")
	if err != nil {
		t.Fatal(err)
	}
	project, err := s.CreateProject(ctx, owner.ID, ProjectInput{Name: "Shared planning"})
	if err != nil {
		t.Fatal(err)
	}
	write := func(user, action, id string, in CollaborationCommand) error {
		return s.CollaborationWrite(ctx, user, project.ID, action, id, in)
	}
	for _, action := range []string{"invite", "role", "remove", "revoke", "accept", "decline", "leave"} {
		if err := write(outsider.ID, action, "private", CollaborationCommand{Email: member.Email, Role: "editor"}); !errors.Is(err, ErrCollaborationNotFound) {
			t.Fatalf("outsider %s = %v", action, err)
		}
	}
	if _, err := s.ProjectCollaboration(ctx, outsider.ID, project.ID); !errors.Is(err, ErrCollaborationNotFound) {
		t.Fatal("private member list", err)
	}
	if err := write(owner.ID, "invite", "", CollaborationCommand{Email: member.Email, Role: "owner"}); !errors.Is(err, ErrCollaborationInvalid) {
		t.Fatal("owner role", err)
	}
	if err := write(owner.ID, "invite", "", CollaborationCommand{Email: member.Email, Role: "editor"}); err != nil {
		t.Fatal(err)
	}
	invites, err := s.CollaborationInvitations(ctx, member.ID)
	if err != nil || len(invites) != 1 {
		t.Fatal("recipient inbox", invites, err)
	}
	invite := invites[0]
	if _, err := s.ProjectCollaboration(ctx, member.ID, project.ID); !errors.Is(err, ErrCollaborationNotFound) {
		t.Fatal("pending invite granted access", err)
	}
	if err := write(outsider.ID, "accept", invite.ID, CollaborationCommand{}); !errors.Is(err, ErrCollaborationNotFound) {
		t.Fatal("stolen invite", err)
	}
	if err := write(member.ID, "accept", invite.ID, CollaborationCommand{}); err != nil {
		t.Fatal(err)
	}
	if err := write(member.ID, "accept", invite.ID, CollaborationCommand{}); err != nil {
		t.Fatal("accept retry", err)
	}
	state, err := s.ProjectCollaboration(ctx, member.ID, project.ID)
	if err != nil || len(state.Members) != 1 || state.Members[0].Role != "editor" || len(state.Invitations) != 0 {
		t.Fatal("accepted membership", state, err)
	}
	// Until the complete authorization adaptation ships, accepting an invite
	// must not accidentally expose tasks through owner-only project endpoints.
	if projects, err := s.ListProjects(ctx, member.ID); err != nil || len(projects) != 1 || !projects[0].IsInbox {
		t.Fatal("project access broadened", projects, err)
	}
	if err := write(member.ID, "invite", "", CollaborationCommand{Email: outsider.Email, Role: "viewer"}); !errors.Is(err, ErrCollaborationNotFound) {
		t.Fatal("editor manages members", err)
	}
	if err := write(owner.ID, "role", member.ID, CollaborationCommand{Role: "viewer"}); err != nil {
		t.Fatal(err)
	}
	if err := write(owner.ID, "role", owner.ID, CollaborationCommand{Role: "viewer"}); !errors.Is(err, ErrCollaborationInvalid) {
		t.Fatal("demote owner", err)
	}
	if err := write(owner.ID, "leave", "", CollaborationCommand{}); !errors.Is(err, ErrCollaborationConflict) {
		t.Fatal("owner left", err)
	}
	if err := write(member.ID, "leave", "", CollaborationCommand{}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.ProjectCollaboration(ctx, member.ID, project.ID); !errors.Is(err, ErrCollaborationNotFound) {
		t.Fatal("left member retains access", err)
	}
	if err := write(member.ID, "accept", invite.ID, CollaborationCommand{}); !errors.Is(err, ErrCollaborationConflict) {
		t.Fatal("revoked invitation accepted", err)
	}
	if err := write(owner.ID, "invite", "", CollaborationCommand{Email: member.Email, Role: "viewer"}); err != nil {
		t.Fatal(err)
	}
	if err := write(member.ID, "decline", invite.ID, CollaborationCommand{}); err != nil {
		t.Fatal(err)
	}
	if err := write(member.ID, "decline", invite.ID, CollaborationCommand{}); err != nil {
		t.Fatal("decline retry", err)
	}
	if err := write(owner.ID, "invite", "", CollaborationCommand{Email: member.Email, Role: "viewer"}); err != nil {
		t.Fatal(err)
	}
	if _, err := s.pool.Exec(ctx, "UPDATE project_invitations SET expires_at=now()-interval '1 second' WHERE id=$1", invite.ID); err != nil {
		t.Fatal(err)
	}
	if err := write(member.ID, "accept", invite.ID, CollaborationCommand{}); !errors.Is(err, ErrCollaborationConflict) {
		t.Fatal("expired invitation", err)
	}
	if err := write(owner.ID, "invite", "", CollaborationCommand{Email: member.Email, Role: "viewer"}); err != nil {
		t.Fatal(err)
	}
	if err := write(owner.ID, "revoke", invite.ID, CollaborationCommand{}); err != nil {
		t.Fatal(err)
	}
	if err := write(member.ID, "accept", invite.ID, CollaborationCommand{}); !errors.Is(err, ErrCollaborationConflict) {
		t.Fatal("owner revocation", err)
	}
	inbox, err := s.EnsureInboxProject(ctx, owner.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := s.CollaborationWrite(ctx, owner.ID, inbox.ID, "invite", "", CollaborationCommand{Email: member.Email, Role: "viewer"}); !errors.Is(err, ErrCollaborationNotFound) {
		t.Fatal("shared inbox", err)
	}
	if err := s.DeleteProject(ctx, owner.ID, project.ID); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := s.pool.QueryRow(ctx, "SELECT count(*) FROM project_invitations WHERE project_id=$1", project.ID).Scan(&count); err != nil || count != 0 {
		t.Fatal("cascade", count, err)
	}
}

func TestCollaborationArchive(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner, _ := s.CreateUser(ctx, "owner-cap@example.com", "unused")
	member, _ := s.CreateUser(ctx, "member-cap@example.com", "unused")
	project, err := s.CreateProject(ctx, owner.ID, ProjectInput{Name: "Capacity"})
	if err != nil {
		t.Fatal(err)
	}
	in := CollaborationCommand{Email: member.Email, Role: "viewer"}
	if err := s.CollaborationWrite(ctx, owner.ID, project.ID, "invite", "", in); err != nil {
		t.Fatal(err)
	}
	invites, err := s.CollaborationInvitations(ctx, member.ID)
	if err != nil || len(invites) != 1 {
		t.Fatal(invites, err)
	}
	if _, err := s.pool.Exec(ctx, "UPDATE projects SET is_archived=true WHERE id=$1", project.ID); err != nil {
		t.Fatal(err)
	}
	if err := s.CollaborationWrite(ctx, member.ID, project.ID, "accept", invites[0].ID, CollaborationCommand{}); !errors.Is(err, ErrCollaborationConflict) {
		t.Fatal("archived accept", err)
	}
	if err := s.CollaborationWrite(ctx, owner.ID, project.ID, "invite", "", in); !errors.Is(err, ErrCollaborationConflict) {
		t.Fatal("archived invite", err)
	}
}

func TestCollaborationBoundedMembership(t *testing.T) {
	s := New(testPool(t))
	ctx := context.Background()
	owner, err := s.CreateUser(ctx, "owner-limit@example.com", "unused")
	if err != nil {
		t.Fatal(err)
	}
	recipient, err := s.CreateUser(ctx, "recipient-limit@example.com", "unused")
	if err != nil {
		t.Fatal(err)
	}
	project, err := s.CreateProject(ctx, owner.ID, ProjectInput{Name: "Limit"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.pool.Exec(ctx, `INSERT INTO users(id,email,password_hash)
		SELECT 'limit-user-'||n,'limit-'||n||'@example.com','unused' FROM generate_series(1,201) n`); err != nil {
		t.Fatal(err)
	}
	if _, err := s.pool.Exec(ctx, `INSERT INTO project_members(project_id,user_id,role)
		SELECT $1,'limit-user-'||n,'viewer' FROM generate_series(1,100) n`, project.ID); err != nil {
		t.Fatal(err)
	}
	in := CollaborationCommand{Email: recipient.Email, Role: "viewer"}
	if err := s.CollaborationWrite(ctx, owner.ID, project.ID, "invite", "", in); err != nil {
		t.Fatal(err)
	}
	invites, err := s.CollaborationInvitations(ctx, recipient.ID)
	if err != nil || len(invites) != 1 {
		t.Fatal(invites, err)
	}
	if err := s.CollaborationWrite(ctx, recipient.ID, project.ID, "accept", invites[0].ID, CollaborationCommand{}); !errors.Is(err, ErrCollaborationConflict) {
		t.Fatal("member quota", err)
	}
	if _, err := s.pool.Exec(ctx, `INSERT INTO project_invitations(id,project_id,recipient_id,role,expires_at)
		SELECT 'limit-invite-'||n,$1,'limit-user-'||n,'viewer',now()+interval '1 day' FROM generate_series(1,199) n`, project.ID); err != nil {
		t.Fatal(err)
	}
	if err := s.CollaborationWrite(ctx, owner.ID, project.ID, "invite", "", in); err != nil {
		t.Fatal("existing recipient retry at quota", err)
	}
	if err := s.CollaborationWrite(ctx, owner.ID, project.ID, "invite", "", CollaborationCommand{Email: "limit-201@example.com", Role: "viewer"}); !errors.Is(err, ErrCollaborationConflict) {
		t.Fatal("invitation quota", err)
	}
}
