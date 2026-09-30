package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

// dbAPI serves the real API over a freshly migrated TEST_DATABASE_URL.
type dbAPI struct {
	t       *testing.T
	handler http.Handler
}

func newDBAPI(t *testing.T) *dbAPI {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}
	ctx := context.Background()
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	if _, err := pool.Exec(ctx, `DROP SCHEMA public CASCADE; CREATE SCHEMA public`); err != nil {
		t.Fatal(err)
	}
	if err := store.Migrate(ctx, pool); err != nil {
		t.Fatal(err)
	}
	data := store.New(pool)
	return &dbAPI{t: t, handler: NewHandler(Config{
		Store:        data,
		ProjectStore: data,
		AuthSecret:   []byte("test-secret-test-secret-test-secret"),
		AuthTokenTTL: time.Hour,
	})}
}

// do sends body (a string is sent as-is, anything else as JSON) and decodes
// the JSON response into out when out is not nil.
func (a *dbAPI) do(method, path, token string, body any, out any) int {
	a.t.Helper()
	var raw []byte
	switch b := body.(type) {
	case nil:
	case string:
		raw = []byte(b)
	default:
		encoded, err := json.Marshal(b)
		if err != nil {
			a.t.Fatal(err)
		}
		raw = encoded
	}
	req := httptest.NewRequest(method, path, bytes.NewReader(raw))
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	a.handler.ServeHTTP(rec, req)
	if out != nil && rec.Body.Len() > 0 {
		if err := json.Unmarshal(rec.Body.Bytes(), out); err != nil {
			a.t.Fatalf("%s %s: decode %q: %v", method, path, rec.Body.String(), err)
		}
	}
	return rec.Code
}

func (a *dbAPI) register(email string) string {
	a.t.Helper()
	var session struct {
		Token string `json:"token"`
	}
	if code := a.do("POST", "/api/v1/auth/register", "", map[string]string{
		"email": email, "password": "long-enough",
	}, &session); code != http.StatusCreated {
		a.t.Fatalf("register %s: %d", email, code)
	}
	return session.Token
}

type projectList struct {
	Projects []store.Project `json:"projects"`
}

type oneProject struct {
	Project store.Project `json:"project"`
}

type apiError struct {
	Error string `json:"error"`
}

func (a *dbAPI) createProject(token string, body map[string]any) store.Project {
	a.t.Helper()
	var created oneProject
	if code := a.do("POST", "/api/v1/projects", token, body, &created); code != http.StatusCreated {
		a.t.Fatalf("create %v: %d", body, code)
	}
	return created.Project
}

func TestProjectsListCreatesOneInbox(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")

	for range 2 {
		var list projectList
		if code := api.do("GET", "/api/v1/projects", token, nil, &list); code != http.StatusOK {
			t.Fatalf("list: %d", code)
		}
		if len(list.Projects) != 1 || !list.Projects[0].IsInbox || list.Projects[0].Name != "صندوق ورودی" {
			t.Fatalf("projects = %+v", list.Projects)
		}
	}
}

func TestProjectsCreateUpdateDelete(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")

	work := api.createProject(token, map[string]any{"name": "  کار  ", "color": "#4073ff", "is_favorite": true})
	if work.Name != "کار" || work.Color != "#4073ff" || !work.IsFavorite || work.Kind != "project" || work.IsInbox {
		t.Fatalf("created = %+v", work)
	}
	folder := api.createProject(token, map[string]any{"name": "Folder", "kind": "folder"})
	if folder.Kind != "folder" || folder.Color == "" {
		t.Fatalf("folder = %+v", folder)
	}
	child := api.createProject(token, map[string]any{"name": "Reports", "parent_id": work.ID})
	if child.ParentID == nil || *child.ParentID != work.ID {
		t.Fatalf("child = %+v", child)
	}

	// An empty parent_id moves the project to the top level.
	var moved oneProject
	if code := api.do("PATCH", "/api/v1/projects/"+child.ID, token,
		map[string]any{"parent_id": "", "name": "گزارش‌ها", "is_archived": true}, &moved); code != http.StatusOK {
		t.Fatalf("patch: %d", code)
	}
	if moved.Project.ParentID != nil || moved.Project.Name != "گزارش‌ها" || !moved.Project.IsArchived {
		t.Fatalf("moved = %+v", moved.Project)
	}

	if code := api.do("DELETE", "/api/v1/projects/"+work.ID, token, nil, nil); code != http.StatusNoContent {
		t.Fatalf("delete: %d", code)
	}
	var failure apiError
	if code := api.do("PATCH", "/api/v1/projects/"+work.ID, token, map[string]any{"name": "x"}, &failure); code != http.StatusNotFound || failure.Error != "project_not_found" {
		t.Fatalf("patch deleted: %d %+v", code, failure)
	}
}

func TestProjectsValidation(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")

	cases := []struct {
		name  string
		body  any
		code  int
		error string
	}{
		{"empty name", map[string]any{"name": "   "}, 400, "invalid_project_name"},
		{"missing name", map[string]any{"color": "#fff"}, 400, "invalid_project_name"},
		{"broken json", "{", 400, "invalid_json"},
		{"unknown parent", map[string]any{"name": "x", "parent_id": "nope"}, 400, "project_create_failed"},
	}
	for _, tc := range cases {
		var failure apiError
		if code := api.do("POST", "/api/v1/projects", token, tc.body, &failure); code != tc.code || failure.Error != tc.error {
			t.Errorf("%s: %d %q, want %d %q", tc.name, code, failure.Error, tc.code, tc.error)
		}
	}
}

func TestInboxIsProtected(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	var list projectList
	api.do("GET", "/api/v1/projects", token, nil, &list)
	inbox := list.Projects[0]
	other := api.createProject(token, map[string]any{"name": "Other"})

	for name, body := range map[string]map[string]any{
		"rename":  {"name": "Mine"},
		"archive": {"is_archived": true},
		"move":    {"parent_id": other.ID},
		"kind":    {"kind": "folder"},
	} {
		var failure apiError
		if code := api.do("PATCH", "/api/v1/projects/"+inbox.ID, token, body, &failure); code != http.StatusConflict || failure.Error != "inbox_project" {
			t.Errorf("%s: %d %+v", name, code, failure)
		}
	}
	var failure apiError
	if code := api.do("DELETE", "/api/v1/projects/"+inbox.ID, token, nil, &failure); code != http.StatusConflict || failure.Error != "inbox_project" {
		t.Errorf("delete: %d %+v", code, failure)
	}

	// Color and favourite are allowed.
	var updated oneProject
	if code := api.do("PATCH", "/api/v1/projects/"+inbox.ID, token,
		map[string]any{"color": "#db4035", "is_favorite": true}, &updated); code != http.StatusOK ||
		updated.Project.Color != "#db4035" || !updated.Project.IsFavorite {
		t.Fatalf("recolor inbox: %d %+v", code, updated.Project)
	}
}

func TestProjectsRequireAuthAndOwnership(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("alice@example.com")
	bob := api.register("bob@example.com")

	if code := api.do("GET", "/api/v1/projects", "", nil, nil); code != http.StatusUnauthorized {
		t.Fatalf("no token: %d", code)
	}
	if code := api.do("GET", "/api/v1/projects", "forged.token.value", nil, nil); code != http.StatusUnauthorized {
		t.Fatalf("bad token: %d", code)
	}

	secret := api.createProject(alice, map[string]any{"name": "Private"})

	// Bob gets 404 for Alice's project, the same as for a missing ID.
	if code := api.do("PATCH", "/api/v1/projects/"+secret.ID, bob, map[string]any{"name": "Mine"}, nil); code != http.StatusNotFound {
		t.Errorf("bob patch: %d", code)
	}
	if code := api.do("DELETE", "/api/v1/projects/"+secret.ID, bob, nil, nil); code != http.StatusNotFound {
		t.Errorf("bob delete: %d", code)
	}
	// Nesting under someone else's project is refused by the owner-scoped
	// foreign key.
	if code := api.do("POST", "/api/v1/projects", bob, map[string]any{"name": "x", "parent_id": secret.ID}, nil); code != http.StatusBadRequest {
		t.Errorf("bob nest under alice: %d", code)
	}

	var bobs projectList
	api.do("GET", "/api/v1/projects", bob, nil, &bobs)
	if len(bobs.Projects) != 1 || !bobs.Projects[0].IsInbox {
		t.Fatalf("bob's projects = %+v", bobs.Projects)
	}
	var alices projectList
	api.do("GET", "/api/v1/projects", alice, nil, &alices)
	if len(alices.Projects) != 2 || alices.Projects[1].Name != "Private" {
		t.Fatalf("alice's projects = %+v", alices.Projects)
	}
}
