package httpapi

import (
	"net/http"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type oneLabel struct {
	Label store.Label `json:"label"`
}

type labelList struct {
	Labels []store.Label `json:"labels"`
}

func (a *dbAPI) createLabel(token string, body map[string]any) store.Label {
	a.t.Helper()
	var result oneLabel
	if code := a.do("POST", "/api/v1/labels", token, body, &result); code != http.StatusCreated {
		a.t.Fatalf("create label %v: %d", body, code)
	}
	return result.Label
}

func TestLabelsLifecycle(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	phone := api.createLabel(token, map[string]any{"name": " @تلفن ", "color": "#3A63D0"})
	if phone.Name != "تلفن" || phone.Color != "#3A63D0" {
		t.Fatalf("created: %+v", phone)
	}
	shop := api.createLabel(token, map[string]any{"name": "خرید"})
	if shop.Color != "#8B88A0" {
		t.Fatalf("default color: %+v", shop)
	}

	// Names are unique per user whatever their case.
	api.createLabel(token, map[string]any{"name": "Work"})
	var failure apiError
	if code := api.do("POST", "/api/v1/labels", token, map[string]any{"name": "work"}, &failure); code != http.StatusConflict || failure.Error != "duplicate_label" {
		t.Fatalf("duplicate: %d %+v", code, failure)
	}

	// Rename, recolor and favourite; favourites list first.
	var edited oneLabel
	if code := api.do("PATCH", "/api/v1/labels/"+shop.ID, token, map[string]any{"name": "بازار", "color": "#C4670F", "is_favorite": true}, &edited); code != http.StatusOK ||
		edited.Label.Name != "بازار" || edited.Label.Color != "#C4670F" || !edited.Label.IsFavorite {
		t.Fatalf("edit: %d %+v", code, edited.Label)
	}
	var list labelList
	api.do("GET", "/api/v1/labels", token, nil, &list)
	if len(list.Labels) != 3 || list.Labels[0].ID != shop.ID {
		t.Fatalf("list: %+v", list.Labels)
	}

	// Labels on tasks, and a label's tasks from every project.
	work := api.createProject(token, map[string]any{"name": "Work"})
	var created oneTask
	if code := api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "Call", "label_ids": []string{phone.ID, shop.ID, phone.ID}}, &created); code != http.StatusCreated ||
		len(created.Task.LabelIDs) != 2 {
		t.Fatalf("create with labels: %d %+v", code, created.Task)
	}
	other := api.createTask(token, work.ID, "Buy")
	if code := api.do("PATCH", "/api/v1/tasks/"+other.ID, token, map[string]any{"label_ids": []string{phone.ID}}, &created); code != http.StatusOK ||
		len(created.Task.LabelIDs) != 1 || created.Task.LabelIDs[0] != phone.ID {
		t.Fatalf("label a task: %d %+v", code, created.Task)
	}
	// Editing something else keeps the labels.
	api.do("PATCH", "/api/v1/tasks/"+other.ID, token, map[string]any{"title": "Buy bread"}, &created)
	if len(created.Task.LabelIDs) != 1 {
		t.Fatalf("plain edit lost labels: %+v", created.Task)
	}
	var tasks taskList
	if code := api.do("GET", "/api/v1/tasks?labelId="+phone.ID, token, nil, &tasks); code != http.StatusOK || len(tasks.Tasks) != 2 {
		t.Fatalf("label tasks: %d %+v", code, tasks.Tasks)
	}
	api.do("GET", "/api/v1/labels", token, nil, &list)
	for _, l := range list.Labels {
		if l.ID == phone.ID && l.OpenTasks != 2 {
			t.Fatalf("open count: %+v", l)
		}
	}

	// Deleting a label keeps its tasks and drops it from them.
	if code := api.do("DELETE", "/api/v1/labels/"+phone.ID, token, nil, nil); code != http.StatusNoContent {
		t.Fatalf("delete: %d", code)
	}
	if got := api.task(token, work.ID, other.ID); len(got.LabelIDs) != 0 {
		t.Fatalf("task kept a deleted label: %+v", got)
	}
}

func TestLabelRules(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("a@example.com")
	bob := api.register("b@example.com")
	mine := api.createLabel(alice, map[string]any{"name": "Mine"})
	bobTask := api.createTask(bob, "", "Bob's")

	expect := func(name string, code int, failure apiError, wantCode int, wantError string) {
		t.Helper()
		if code != wantCode || failure.Error != wantError {
			t.Fatalf("%s: %d %+v", name, code, failure)
		}
	}
	for name, body := range map[string]map[string]any{
		"empty name": {"name": "  "},
		"long name":  {"name": string(make([]rune, 61))},
		"bad color":  {"name": "x", "color": "red"},
		"line break": {"name": "a\nb"},
	} {
		var failure apiError
		code := api.do("POST", "/api/v1/labels", alice, body, &failure)
		expect(name, code, failure, http.StatusBadRequest, "invalid_label")
	}

	// Another user's label does not exist for them.
	var failure apiError
	code := api.do("PATCH", "/api/v1/labels/"+mine.ID, bob, map[string]any{"name": "x"}, &failure)
	expect("foreign update", code, failure, http.StatusNotFound, "label_not_found")
	failure = apiError{}
	code = api.do("DELETE", "/api/v1/labels/"+mine.ID, bob, nil, &failure)
	expect("foreign delete", code, failure, http.StatusNotFound, "label_not_found")
	failure = apiError{}
	code = api.do("GET", "/api/v1/tasks?labelId="+mine.ID, bob, nil, &failure)
	expect("foreign label tasks", code, failure, http.StatusNotFound, "label_not_found")
	failure = apiError{}
	code = api.do("PATCH", "/api/v1/tasks/"+bobTask.ID, bob, map[string]any{"label_ids": []string{mine.ID}}, &failure)
	expect("foreign label on task", code, failure, http.StatusNotFound, "label_not_found")
	var list labelList
	api.do("GET", "/api/v1/labels", bob, nil, &list)
	if len(list.Labels) != 0 {
		t.Fatalf("bob sees labels: %+v", list.Labels)
	}
	if code := api.do("GET", "/api/v1/labels", "", nil, nil); code != http.StatusUnauthorized {
		t.Fatalf("anonymous: %d", code)
	}
}
