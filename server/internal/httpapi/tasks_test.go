package httpapi

import (
	"strings"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type oneTask struct {
	Task store.Task `json:"task"`
}

type taskList struct {
	Tasks []store.Task `json:"tasks"`
}

func (a *dbAPI) createTask(token, project, title string) store.Task {
	a.t.Helper()
	var result oneTask
	if code := a.do("POST", "/api/v1/tasks", token, map[string]any{"title": title, "project_id": project}, &result); code != 201 {
		a.t.Fatalf("create task: %d", code)
	}
	return result.Task
}

func TestTasksLifecycle(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	task := api.createTask(token, "", "  بخونم  ")
	if task.Title != "بخونم" || task.Priority != 4 || task.ProjectID == "" {
		t.Fatalf("defaults: %+v", task)
	}
	path := "/api/v1/tasks/" + task.ID
	other := api.createProject(token, map[string]any{"name": "Study"})
	var edited oneTask
	if code := api.do("PATCH", path, token, map[string]any{"project_id": other.ID, "priority": 1, "description": "**DDIA**"}, &edited); code != 200 || edited.Task.ProjectID != other.ID || edited.Task.Priority != 1 || edited.Task.Description != "**DDIA**" {
		t.Fatalf("edit: %d %+v", code, edited)
	}
	for range 2 {
		if code := api.do("POST", path+"/close", token, nil, &edited); code != 200 || edited.Task.CompletedAt == nil {
			t.Fatalf("close: %d %+v", code, edited)
		}
	}
	var list taskList
	api.do("GET", "/api/v1/tasks?projectId="+other.ID, token, nil, &list)
	if len(list.Tasks) != 0 {
		t.Fatal("completed task visible by default")
	}
	api.do("GET", "/api/v1/tasks?projectId="+other.ID+"&showCompleted=true", token, nil, &list)
	if len(list.Tasks) != 1 {
		t.Fatal("completed task missing")
	}
	if code := api.do("POST", path+"/reopen", token, nil, &edited); code != 200 || edited.Task.CompletedAt != nil {
		t.Fatalf("reopen: %d %+v", code, edited)
	}
	if code := api.do("DELETE", path, token, nil, nil); code != 204 {
		t.Fatalf("delete: %d", code)
	}
	if code := api.do("PATCH", path, token, map[string]any{"title": "x"}, nil); code != 404 {
		t.Fatalf("edit deleted: %d", code)
	}
	if code := api.do("POST", path+"/restore", token, nil, &edited); code != 200 || edited.Task.ID != task.ID || edited.Task.Priority != 1 {
		t.Fatalf("restore: %d %+v", code, edited)
	}
}

func TestTasksValidationAndOwnership(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("alice@example.com")
	bob := api.register("bob@example.com")
	project := api.createProject(alice, map[string]any{"name": "Private"})
	task := api.createTask(alice, project.ID, "Secret")
	path := "/api/v1/tasks/" + task.ID
	for _, action := range []string{"close", "reopen", "restore"} {
		if code := api.do("POST", path+"/"+action, bob, nil, nil); code != 404 {
			t.Errorf("foreign %s: %d", action, code)
		}
	}
	for _, method := range []string{"PATCH", "DELETE"} {
		if code := api.do(method, path, bob, map[string]any{"title": "x"}, nil); code != 404 {
			t.Errorf("foreign %s: %d", method, code)
		}
	}
	if code := api.do("GET", "/api/v1/tasks?projectId="+project.ID, bob, nil, nil); code != 404 {
		t.Fatalf("foreign project list: %d", code)
	}
	if code := api.do("POST", "/api/v1/tasks", bob, map[string]any{"title": "x", "project_id": project.ID}, nil); code != 404 {
		t.Fatalf("foreign project: %d", code)
	}
	for _, body := range []any{
		map[string]any{"title": " "},
		map[string]any{"title": strings.Repeat("x", 501)},
		map[string]any{"title": "x", "description": strings.Repeat("x", 20001)},
		map[string]any{"title": "x", "priority": 5},
		map[string]any{"title": "x", "owner_id": "forged"},
		`{"title":"x"} {}`,
		strings.Repeat("x", 130000),
	} {
		if code := api.do("POST", "/api/v1/tasks", alice, body, nil); code != 400 {
			t.Errorf("invalid create: %d", code)
		}
	}
	for _, body := range []any{map[string]any{"title": " "}, map[string]any{"priority": 0}} {
		if code := api.do("PATCH", path, alice, body, nil); code != 400 {
			t.Errorf("invalid patch: %d", code)
		}
	}
	for _, endpoint := range []struct{ method, path string }{
		{"GET", "/api/v1/tasks?projectId=" + project.ID},
		{"POST", "/api/v1/tasks"},
		{"PATCH", path},
		{"DELETE", path},
		{"POST", path + "/close"},
		{"POST", "/api/v1/tasks/reorder"},
	} {
		if code := api.do(endpoint.method, endpoint.path, "", nil, nil); code != 401 {
			t.Errorf("unauthenticated %s: %d", endpoint.path, code)
		}
	}
}

func TestTaskReorderIsAtomic(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("alice@example.com")
	bob := api.register("bob@example.com")
	project := api.createProject(alice, map[string]any{"name": "Work"})
	a := api.createTask(alice, project.ID, "a")
	b := api.createTask(alice, project.ID, "b")
	foreign := api.createTask(bob, "", "private")
	if code := api.do("POST", "/api/v1/tasks/reorder", alice, map[string]any{"project_id": project.ID, "task_ids": []string{b.ID, a.ID}}, nil); code != 204 {
		t.Fatalf("reorder: %d", code)
	}
	for _, ids := range [][]string{{a.ID, foreign.ID}, {a.ID, "missing"}, {a.ID, a.ID}, {}} {
		code := api.do("POST", "/api/v1/tasks/reorder", alice, map[string]any{"project_id": project.ID, "task_ids": ids}, nil)
		if code != 400 && code != 404 {
			t.Errorf("invalid reorder: %d", code)
		}
	}
	var list taskList
	api.do("GET", "/api/v1/tasks?projectId="+project.ID, alice, nil, &list)
	if len(list.Tasks) != 2 || list.Tasks[0].ID != b.ID || list.Tasks[1].ID != a.ID {
		t.Fatalf("order changed after failed request: %+v", list)
	}
}
