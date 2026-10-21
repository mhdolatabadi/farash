package httpapi

import (
	"context"
	"errors"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

func TestSyncAPIAuthValidationAndPrivacy(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("sync-api-a@example.com")
	bob := api.register("sync-api-b@example.com")
	task := api.createTask(alice, "", "Private sync task")
	api.createTask(bob, "", "Bob only")
	if code := api.do("POST", "/api/v1/sync", "", map[string]any{}, nil); code != 401 {
		t.Fatal("auth", code)
	}
	for _, body := range []any{map[string]any{"cursor": "wrong"}, map[string]any{"limit": -1}, map[string]any{"limit": 501}, map[string]any{"owner_id": "forged"}, `{} {}`} {
		if code := api.do("POST", "/api/v1/sync", alice, body, nil); code != 400 {
			t.Fatal("validation", code, body)
		}
	}
	var page store.SyncPage
	if code := api.do("POST", "/api/v1/sync", alice, map[string]any{}, &page); code != 200 || page.Version != 1 || len(page.Changes) != 2 || page.HasMore {
		t.Fatal(code, page)
	}
	found := false
	for _, change := range page.Changes {
		if change.Entity == "tasks" && change.ID == task.ID {
			found = true
		}
	}
	if !found {
		t.Fatal("task missing", page)
	}
	if code := api.do("POST", "/api/v1/sync", bob, map[string]any{"cursor": page.Cursor}, nil); code != 400 {
		t.Fatal("foreign cursor", code)
	}
	if code := api.do("POST", "/api/v1/sync", alice, map[string]any{"cursor": page.Cursor}, &page); code != 200 || len(page.Changes) != 0 {
		t.Fatal("idle sync", code, page)
	}
}

type unavailableSync struct{ *fakeUsers }

func (unavailableSync) PullSync(context.Context, string, string, int) (store.SyncPage, error) {
	return store.SyncPage{}, errors.New("private database connection details")
}

func TestSyncFailureDoesNotLeakDetails(t *testing.T) {
	api := &dbAPI{t: t, handler: NewHandler(Config{
		Store:      unavailableSync{newFakeUsers()},
		AuthSecret: []byte("test-secret"),
	})}
	token := api.register("sync-failure@example.com")
	var failure apiError
	if code := api.do("POST", "/api/v1/sync", token, map[string]any{}, &failure); code != 500 || failure.Error != "sync_unavailable" {
		t.Fatal(code, failure)
	}
}
