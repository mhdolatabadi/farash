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
		Store: data, Projects: data,
		AuthSecret: []byte("test-secret-test-secret-test-secret"), AuthTokenTTL: time.Hour,
	})}
}

// do sends a JSON request and decodes a JSON response into out (if not nil).
func (a *dbAPI) do(method, path, token string, body any, out any) int {
	a.t.Helper()
	var reader *bytes.Reader
	switch b := body.(type) {
	case nil:
		reader = bytes.NewReader(nil)
	case string:
		reader = bytes.NewReader([]byte(b))
	default:
		encoded, err := json.Marshal(b)
		if err != nil {
			a.t.Fatal(err)
		}
		reader = bytes.NewReader(encoded)
	}
	req := httptest.NewRequest(method, path, reader)
	req.RemoteAddr = "192.0.2.1:1234"
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
	Projects []projectResponse `json:"projects"`
}

type apiError struct {
	Error string `json:"error"`
}

func TestProjectsAPI(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")

	var list projectList
	if code := api.do("GET", "/api/v1/projects", token, nil, &list); code != http.StatusOK {
		t.Fatalf("list: %d", code)
	}
	if len(list.Projects) != 1 || !list.Projects[0].IsInbox {
		t.Fatalf("new account projects = %+v", list.Projects)
	}
	inbox := list.Projects[0]

	var work projectResponse
	if code := api.do("POST", "/api/v1/projects", token,
		map[string]any{"name": "  کار  ", "color": "blue", "isFavorite": true}, &work); code != http.StatusCreated {
		t.Fatalf("create: %d", code)
	}
	if work.Name != "کار" || work.Color != "blue" || !work.IsFavorite || work.ParentID != nil {
		t.Fatalf("created = %+v", work)
	}

	var child projectResponse
	if code := api.do("POST", "/api/v1/projects", token,
		map[string]any{"name": "Reports", "parentId": work.ID}, &child); code != http.StatusCreated {
		t.Fatalf("create child: %d", code)
	}
	if child.Color != "charcoal" || child.ParentID == nil || *child.ParentID != work.ID {
		t.Fatalf("child = %+v", child)
	}

	// parentId: null moves to the top level; other fields stay.
	var moved projectResponse
	if code := api.do("PATCH", "/api/v1/projects/"+child.ID, token,
		`{"parentId": null, "name": "گزارش‌ها"}`, &moved); code != http.StatusOK {
		t.Fatalf("patch: %d", code)
	}
	if moved.ParentID != nil || moved.Name != "گزارش‌ها" || moved.Color != "charcoal" {
		t.Fatalf("moved = %+v", moved)
	}

	if code := api.do("POST", "/api/v1/projects/reorder", token,
		map[string]any{"ids": []string{child.ID, work.ID}}, nil); code != http.StatusNoContent {
		t.Fatalf("reorder: %d", code)
	}
	api.do("GET", "/api/v1/projects", token, nil, &list)
	if len(list.Projects) != 3 || list.Projects[1].ID != child.ID || list.Projects[2].ID != work.ID {
		t.Fatalf("after reorder = %+v", list.Projects)
	}

	var archived projectResponse
	api.do("PATCH", "/api/v1/projects/"+work.ID, token, `{"isArchived": true}`, &archived)
	if !archived.IsArchived {
		t.Fatalf("archive = %+v", archived)
	}
	api.do("GET", "/api/v1/projects?archived=true", token, nil, &list)
	if len(list.Projects) != 1 || list.Projects[0].ID != work.ID {
		t.Fatalf("archived list = %+v", list.Projects)
	}

	if code := api.do("DELETE", "/api/v1/projects/"+work.ID, token, nil, nil); code != http.StatusNoContent {
		t.Fatalf("delete: %d", code)
	}
	if code := api.do("GET", "/api/v1/projects/"+work.ID, token, nil, nil); code != http.StatusNotFound {
		t.Fatalf("get deleted: %d", code)
	}

	var failure apiError
	if code := api.do("DELETE", "/api/v1/projects/"+inbox.ID, token, nil, &failure); code != http.StatusBadRequest || failure.Error != "inbox_protected" {
		t.Fatalf("delete inbox: %d %+v", code, failure)
	}
}

func TestProjectsValidation(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	var project projectResponse
	api.do("POST", "/api/v1/projects", token, map[string]any{"name": "P"}, &project)

	long := make([]rune, 121)
	for i := range long {
		long[i] = 'ا'
	}
	cases := []struct {
		name, method, path string
		body               any
		code               int
		error              string
	}{
		{"empty name", "POST", "/api/v1/projects", map[string]any{"name": "   "}, 400, "invalid_name"},
		{"long name", "POST", "/api/v1/projects", map[string]any{"name": string(long)}, 400, "invalid_name"},
		{"multi-line name", "POST", "/api/v1/projects", map[string]any{"name": "a\nb"}, 400, "invalid_name"},
		{"bad color", "POST", "/api/v1/projects", map[string]any{"name": "x", "color": "#fff"}, 400, "invalid_color"},
		{"unknown field", "POST", "/api/v1/projects", map[string]any{"name": "x", "owner": "y"}, 400, "invalid_json"},
		{"missing parent", "POST", "/api/v1/projects", map[string]any{"name": "x", "parentId": "nope"}, 400, "invalid_parent"},
		{"broken json", "POST", "/api/v1/projects", "{", 400, "invalid_json"},
		{"patch unknown field", "PATCH", "/api/v1/projects/" + project.ID, `{"owner": "x"}`, 400, "unknown_field"},
		{"patch null favorite", "PATCH", "/api/v1/projects/" + project.ID, `{"isFavorite": null}`, 400, "invalid_json"},
		{"patch bad color", "PATCH", "/api/v1/projects/" + project.ID, `{"color": "pink"}`, 400, "invalid_color"},
		{"self parent", "PATCH", "/api/v1/projects/" + project.ID, map[string]any{"parentId": project.ID}, 400, "invalid_parent"},
		{"empty reorder", "POST", "/api/v1/projects/reorder", map[string]any{"ids": []string{}}, 400, "invalid_order"},
	}
	for _, tc := range cases {
		var failure apiError
		code := api.do(tc.method, tc.path, token, tc.body, &failure)
		if code != tc.code || failure.Error != tc.error {
			t.Errorf("%s: %d %q, want %d %q", tc.name, code, failure.Error, tc.code, tc.error)
		}
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

	var secret projectResponse
	api.do("POST", "/api/v1/projects", alice, map[string]any{"name": "Private"}, &secret)

	// Bob sees 404 for everything of Alice's, the same as for a missing ID.
	for _, request := range []struct {
		method string
		path   string
		body   any
	}{
		{"GET", "/api/v1/projects/" + secret.ID, nil},
		{"PATCH", "/api/v1/projects/" + secret.ID, map[string]any{"name": "Mine"}},
		{"DELETE", "/api/v1/projects/" + secret.ID, nil},
		{"POST", "/api/v1/projects/reorder", map[string]any{"ids": []string{secret.ID}}},
	} {
		if code := api.do(request.method, request.path, bob, request.body, nil); code != http.StatusNotFound {
			t.Errorf("%s %s as bob: %d", request.method, request.path, code)
		}
	}
	var failure apiError
	if code := api.do("POST", "/api/v1/projects", bob,
		map[string]any{"name": "x", "parentId": secret.ID}, &failure); code != http.StatusBadRequest || failure.Error != "invalid_parent" {
		t.Errorf("nest under alice's: %d %+v", code, failure)
	}

	var bobs projectList
	api.do("GET", "/api/v1/projects", bob, nil, &bobs)
	if len(bobs.Projects) != 1 || !bobs.Projects[0].IsInbox {
		t.Fatalf("bob's projects = %+v", bobs.Projects)
	}
	var still projectResponse
	if code := api.do("GET", "/api/v1/projects/"+secret.ID, alice, nil, &still); code != http.StatusOK || still.Name != "Private" {
		t.Fatalf("alice's project changed: %d %+v", code, still)
	}
}
