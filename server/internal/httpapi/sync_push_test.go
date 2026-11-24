package httpapi

import (
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

func TestOfflineSyncTaskCreateReplayAndOwnership(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("sync-push-alice@example.com")
	bob := api.register("sync-push-bob@example.com")
	path := "/api/v1/sync/tasks"
	body := map[string]any{"title": "Offline capture", "request_key": "offline-create-req-0001"}
	var first, replay, other struct {
		Task store.Task `json:"task"`
	}
	if code := api.do("POST", path, "", body, nil); code != 401 {
		t.Fatalf("unauthenticated: %d", code)
	}
	if code := api.do("POST", path, alice, map[string]any{"title": "No key"}, nil); code != 400 {
		t.Fatalf("missing request key: %d", code)
	}
	if code := api.do("POST", path, alice, body, &first); code != 201 {
		t.Fatalf("first create: %d", code)
	}
	if code := api.do("POST", path, alice, body, &replay); code != 201 || replay.Task.ID != first.Task.ID {
		t.Fatalf("replay duplicated task: %d %+v %+v", code, first, replay)
	}
	if code := api.do("POST", path, alice, map[string]any{"title": "Changed", "request_key": "offline-create-req-0001"}, nil); code != 409 {
		t.Fatalf("changed payload accepted: %d", code)
	}
	if code := api.do("POST", path, bob, body, &other); code != 201 || other.Task.ID == first.Task.ID {
		t.Fatalf("cross-owner replay leaked task: %d", code)
	}
	if code := api.do("DELETE", "/api/v1/tasks/"+first.Task.ID, alice, nil, nil); code != 204 {
		t.Fatalf("delete: %d", code)
	}
	if code := api.do("POST", path, alice, body, &replay); code != 201 || replay.Task.ID != first.Task.ID {
		t.Fatalf("replay resurrected deleted task: %d", code)
	}
	var list taskList
	if code := api.do("GET", "/api/v1/tasks?projectId="+first.Task.ProjectID, alice, nil, &list); code != 200 || len(list.Tasks) != 0 {
		t.Fatalf("deleted task reappeared: %d %+v", code, list)
	}
}
