package httpapi

import (
	"net/http"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

func (a *dbAPI) createSubtask(token, parent, title string) store.Task {
	a.t.Helper()
	var result oneTask
	if code := a.do("POST", "/api/v1/tasks", token, map[string]any{"title": title, "parent_id": parent}, &result); code != http.StatusCreated {
		a.t.Fatalf("create subtask %q: %d", title, code)
	}
	return result.Task
}

func (a *dbAPI) task(token, project, id string) store.Task {
	a.t.Helper()
	var list taskList
	a.do("GET", "/api/v1/tasks?projectId="+project+"&showCompleted=true", token, nil, &list)
	for _, task := range list.Tasks {
		if task.ID == id {
			return task
		}
	}
	a.t.Fatalf("task %s not listed in %s", id, project)
	return store.Task{}
}

func parentOf(task store.Task) string {
	if task.ParentID == nil {
		return ""
	}
	return *task.ParentID
}

func TestSubtasksFollowTheirParent(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	work := api.createProject(token, map[string]any{"name": "Work"})
	home := api.createProject(token, map[string]any{"name": "Home"})
	backlog := api.createSection(token, work.ID, "Backlog")

	var created oneTask
	api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "Trip", "section_id": backlog.ID}, &created)
	trip := created.Task
	tickets := api.createSubtask(token, trip.ID, "Tickets")
	if tickets.ProjectID != work.ID || tickets.SectionID == nil || *tickets.SectionID != backlog.ID || parentOf(tickets) != trip.ID {
		t.Fatalf("subtask placement: %+v", tickets)
	}
	seat := api.createSubtask(token, tickets.ID, "Seat")
	api.createSubtask(token, trip.ID, "Hotel")

	trip = api.task(token, work.ID, trip.ID)
	if trip.SubtaskCount != 2 || trip.CompletedSubtaskCount != 0 {
		t.Fatalf("counts: %+v", trip)
	}

	// Moving the parent carries the whole subtree.
	var edited oneTask
	if code := api.do("PATCH", "/api/v1/tasks/"+trip.ID, token, map[string]any{"project_id": home.ID}, &edited); code != http.StatusOK || edited.Task.SectionID != nil {
		t.Fatalf("move parent: %d %+v", code, edited.Task)
	}
	moved := api.task(token, home.ID, seat.ID)
	if moved.SectionID != nil || parentOf(moved) != tickets.ID {
		t.Fatalf("grandchild did not follow: %+v", moved)
	}

	// Moving a subtask elsewhere on its own makes it top-level.
	if code := api.do("PATCH", "/api/v1/tasks/"+seat.ID, token, map[string]any{"project_id": work.ID}, &edited); code != http.StatusOK || edited.Task.ParentID != nil {
		t.Fatalf("move subtask out: %d %+v", code, edited.Task)
	}

	// Indent under a task, then outdent.
	if code := api.do("PATCH", "/api/v1/tasks/"+seat.ID, token, map[string]any{"parent_id": tickets.ID}, &edited); code != http.StatusOK ||
		parentOf(edited.Task) != tickets.ID || edited.Task.ProjectID != home.ID {
		t.Fatalf("indent: %d %+v", code, edited.Task)
	}
	if code := api.do("PATCH", "/api/v1/tasks/"+seat.ID, token, map[string]any{"parent_id": ""}, &edited); code != http.StatusOK ||
		edited.Task.ParentID != nil || edited.Task.ProjectID != home.ID {
		t.Fatalf("outdent: %d %+v", code, edited.Task)
	}
	// Editing other fields keeps the parent.
	if code := api.do("PATCH", "/api/v1/tasks/"+tickets.ID, token, map[string]any{"title": "Train tickets", "project_id": home.ID}, &edited); code != http.StatusOK || parentOf(edited.Task) != trip.ID {
		t.Fatalf("plain edit lost parent: %d %+v", code, edited.Task)
	}
}

func TestCompletingAndDeletingCascade(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	project := api.createProject(token, map[string]any{"name": "Work"})
	parent := api.createTask(token, project.ID, "Release")
	done := api.createSubtask(token, parent.ID, "Notes")
	open := api.createSubtask(token, parent.ID, "Build")
	deep := api.createSubtask(token, open.ID, "Sign")

	// A subtask closed earlier stays closed when the parent reopens.
	api.do("POST", "/api/v1/tasks/"+done.ID+"/close", token, nil, nil)
	if p := api.task(token, project.ID, parent.ID); p.CompletedSubtaskCount != 1 || p.SubtaskCount != 2 {
		t.Fatalf("progress: %+v", p)
	}
	var result oneTask
	api.do("POST", "/api/v1/tasks/"+parent.ID+"/close", token, nil, &result)
	if result.Task.CompletedSubtaskCount != 2 || api.task(token, project.ID, deep.ID).CompletedAt == nil {
		t.Fatalf("close did not cascade: %+v", result.Task)
	}
	api.do("POST", "/api/v1/tasks/"+parent.ID+"/reopen", token, nil, &result)
	if api.task(token, project.ID, open.ID).CompletedAt != nil || api.task(token, project.ID, deep.ID).CompletedAt != nil {
		t.Fatal("reopen did not bring back the subtasks closed with it")
	}
	if api.task(token, project.ID, done.ID).CompletedAt == nil {
		t.Fatal("reopen reopened a subtask closed on its own")
	}

	// Reopening a subtask reopens its completed ancestors.
	api.do("POST", "/api/v1/tasks/"+parent.ID+"/close", token, nil, nil)
	api.do("POST", "/api/v1/tasks/"+deep.ID+"/reopen", token, nil, nil)
	if api.task(token, project.ID, parent.ID).CompletedAt != nil || api.task(token, project.ID, open.ID).CompletedAt != nil {
		t.Fatal("ancestors stayed completed above an open subtask")
	}

	// Deleting removes the subtree; restoring brings back what went with it.
	api.do("DELETE", "/api/v1/tasks/"+deep.ID, token, nil, nil)
	if code := api.do("DELETE", "/api/v1/tasks/"+parent.ID, token, nil, nil); code != http.StatusNoContent {
		t.Fatalf("delete: %d", code)
	}
	var list taskList
	api.do("GET", "/api/v1/tasks?projectId="+project.ID+"&showCompleted=true", token, nil, &list)
	if len(list.Tasks) != 0 {
		t.Fatalf("subtasks outlived their parent: %+v", list.Tasks)
	}
	api.do("POST", "/api/v1/tasks/"+parent.ID+"/restore", token, nil, &result)
	api.do("GET", "/api/v1/tasks?projectId="+project.ID+"&showCompleted=true", token, nil, &list)
	if len(list.Tasks) != 3 || result.Task.SubtaskCount != 2 {
		t.Fatalf("restore: %d tasks, %+v", len(list.Tasks), result.Task)
	}
	// The one deleted on its own comes back top-level if its parent is gone.
	api.do("DELETE", "/api/v1/tasks/"+open.ID, token, nil, nil)
	api.do("POST", "/api/v1/tasks/"+deep.ID+"/restore", token, nil, &result)
	if result.Task.ParentID != nil {
		t.Fatalf("restored under a deleted parent: %+v", result.Task)
	}
}

func TestSubtaskRules(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	intruder := api.register("b@example.com")
	work := api.createProject(token, map[string]any{"name": "Work"})
	home := api.createProject(token, map[string]any{"name": "Home"})
	root := api.createTask(token, work.ID, "Root")
	child := api.createSubtask(token, root.ID, "Child")

	expect := func(name string, code int, failure apiError, wantCode int, wantError string) {
		t.Helper()
		if code != wantCode || failure.Error != wantError {
			t.Fatalf("%s: %d %+v", name, code, failure)
		}
	}
	var failure apiError
	code := api.do("PATCH", "/api/v1/tasks/"+root.ID, token, map[string]any{"parent_id": child.ID}, &failure)
	expect("cycle", code, failure, http.StatusBadRequest, "invalid_parent")
	failure = apiError{}
	code = api.do("PATCH", "/api/v1/tasks/"+root.ID, token, map[string]any{"parent_id": root.ID}, &failure)
	expect("self", code, failure, http.StatusBadRequest, "invalid_parent")
	failure = apiError{}
	code = api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "x", "parent_id": root.ID, "project_id": home.ID}, &failure)
	expect("other project", code, failure, http.StatusBadRequest, "invalid_parent")
	failure = apiError{}
	code = api.do("PATCH", "/api/v1/tasks/"+child.ID, token, map[string]any{"parent_id": root.ID, "project_id": home.ID}, &failure)
	expect("indent into another project", code, failure, http.StatusBadRequest, "invalid_parent")

	// Another user's task is not a parent and does not exist for them.
	failure = apiError{}
	code = api.do("POST", "/api/v1/tasks", intruder, map[string]any{"title": "x", "parent_id": root.ID}, &failure)
	expect("foreign parent", code, failure, http.StatusNotFound, "parent_not_found")
	mine := api.createTask(intruder, "", "Mine")
	failure = apiError{}
	code = api.do("PATCH", "/api/v1/tasks/"+mine.ID, intruder, map[string]any{"parent_id": root.ID}, &failure)
	expect("indent under foreign task", code, failure, http.StatusNotFound, "parent_not_found")
	failure = apiError{}
	code = api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "x", "parent_id": "missing"}, &failure)
	expect("missing parent", code, failure, http.StatusNotFound, "parent_not_found")

	// No new open subtasks under a completed task.
	api.do("POST", "/api/v1/tasks/"+root.ID+"/close", token, nil, nil)
	failure = apiError{}
	code = api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "x", "parent_id": root.ID}, &failure)
	expect("completed parent", code, failure, http.StatusBadRequest, "invalid_parent")
	api.do("POST", "/api/v1/tasks/"+root.ID+"/reopen", token, nil, nil)

	// Five levels at most, counting the subtree being moved.
	level := child
	for i := 3; i <= 5; i++ {
		level = api.createSubtask(token, level.ID, "Level")
	}
	failure = apiError{}
	code = api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "Too deep", "parent_id": level.ID}, &failure)
	expect("sixth level", code, failure, http.StatusBadRequest, "invalid_parent")
	other := api.createTask(token, work.ID, "Other")
	api.createSubtask(token, other.ID, "Under other")
	failure = apiError{}
	code = api.do("PATCH", "/api/v1/tasks/"+other.ID, token, map[string]any{"parent_id": level.ID}, &failure)
	expect("subtree too deep", code, failure, http.StatusBadRequest, "invalid_parent")

	failure = apiError{}
	code = api.do("PATCH", "/api/v1/tasks/"+other.ID, token, map[string]any{"parent_id": 7}, &failure)
	expect("parent type", code, failure, http.StatusBadRequest, "invalid_json")
}
