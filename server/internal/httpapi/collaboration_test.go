package httpapi

import (
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

func TestCollaborationAPI(t *testing.T) {
	api := newDBAPI(t)
	owner := api.register("collab-api-owner@example.com")
	member := api.register("collab-api-member@example.com")
	other := api.register("collab-api-other@example.com")
	project := api.createProject(owner, map[string]any{"name": "Shared"})
	base := "/api/v1/projects/" + project.ID + "/collaboration"
	routes := []struct{ method, path string }{
		{"GET", base}, {"POST", base + "/invitations"},
		{"DELETE", base + "/invitations/private"},
		{"POST", base + "/invitations/private/accept"},
		{"POST", base + "/invitations/private/decline"},
		{"PATCH", base + "/members/private"},
		{"DELETE", base + "/members/private"}, {"POST", base + "/leave"},
	}
	for _, route := range routes {
		if code := api.do(route.method, route.path, "", map[string]any{}, nil); code != 401 {
			t.Fatal("auth", route, code)
		}
		if code := api.do(route.method, route.path, other, map[string]any{}, nil); code != 404 {
			t.Fatal("private", route, code)
		}
	}
	if code := api.do("GET", "/api/v1/collaboration/invitations", "", nil, nil); code != 401 {
		t.Fatal("invitation auth", code)
	}
	if code := api.do("POST", base+"/invitations", owner, map[string]any{"email": "collab-api-member@example.com", "role": "owner"}, nil); code != 400 {
		t.Fatal("invalid role", code)
	}
	if code := api.do("POST", base+"/invitations", owner, map[string]any{"email": "collab-api-member@example.com", "role": "editor"}, nil); code != 204 {
		t.Fatal("invite", code)
	}
	var invites []store.ProjectInvitation
	if code := api.do("GET", "/api/v1/collaboration/invitations", member, nil, &invites); code != 200 || len(invites) != 1 {
		t.Fatal("inbox", code, invites)
	}
	if code := api.do("GET", base, member, nil, nil); code != 404 {
		t.Fatal("pending", code)
	}
	if code := api.do("POST", base+"/invitations/"+invites[0].ID+"/accept", member, nil, nil); code != 204 {
		t.Fatal("accept", code)
	}
	var state store.ProjectCollaboration
	if code := api.do("GET", base, member, nil, &state); code != 200 || len(state.Members) != 1 || len(state.Invitations) != 0 {
		t.Fatal("member", code, state)
	}
	if code := api.do("PATCH", base+"/members/"+invites[0].RecipientID, owner, map[string]any{"role": "viewer"}, nil); code != 204 {
		t.Fatal("role", code)
	}
	if code := api.do("DELETE", base+"/members/"+invites[0].RecipientID, owner, nil, nil); code != 204 {
		t.Fatal("remove", code)
	}
	if code := api.do("GET", base, member, nil, nil); code != 404 {
		t.Fatal("removed", code)
	}
	// Per-user mutation throttling bounds even invalid invitation attempts.
	for i := 0; i < 20; i++ {
		api.do("POST", base+"/invitations", owner, map[string]any{"email": "", "role": "editor"}, nil)
	}
	if code := api.do("POST", base+"/invitations", owner, map[string]any{"email": "", "role": "editor"}, nil); code != 429 {
		t.Fatal("rate limit", code)
	}
}
