package httpapi

import (
	"github.com/mhdolatabadi/farash/server/internal/store"
	"testing"
)

func TestScrumAPI(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("scrum-api@example.com")
	other := api.register("scrum-private@example.com")
	p := api.createProject(token, map[string]any{"name": "Personal"})
	base := "/api/v1/projects/" + p.ID + "/agile"
	for _, v := range []struct{ method, path string }{{"GET", base}, {"PATCH", base}, {"PUT", base + "/items/x"}, {"POST", base + "/sprints"}, {"PATCH", base + "/sprints/x"}, {"POST", base + "/sprints/x/start"}, {"POST", base + "/sprints/x/close"}, {"PATCH", base + "/sprints/x/notes"}} {
		if code := api.do(v.method, v.path, "", map[string]any{}, nil); code != 401 {
			t.Fatal("auth", v, code)
		}
		if code := api.do(v.method, v.path, other, map[string]any{}, nil); code != 404 {
			t.Fatal("private", v, code)
		}
	}
	if c := api.do("PATCH", base, token, map[string]any{"method": "bad"}, nil); c != 400 {
		t.Fatal(c)
	}
	if c := api.do("PATCH", base, token, map[string]any{"method": "scrum"}, nil); c != 200 {
		t.Fatal(c)
	}
	var data store.AgileWorkspace
	if c := api.do("POST", base+"/sprints", token, map[string]any{"name": "Test", "starts_on": "2026-01-01", "ends_on": "2026-01-14", "request_key": "api-sprint-key"}, &data); c != 200 || len(data.Sprints) != 1 {
		t.Fatal(c, data)
	}
	if c := api.do("POST", base+"/sprints/"+data.Sprints[0].ID+"/start", token, map[string]any{}, nil); c != 400 {
		t.Fatal("empty start", c)
	}
	task := api.createTask(token, p.ID, "Work")
	if c := api.do("PUT", base+"/items/"+task.ID, token, map[string]any{"issue_type": "story", "points": -1, "stage": "todo"}, nil); c != 400 {
		t.Fatal("points", c)
	}
	if c := api.do("PUT", base+"/items/"+task.ID, token, map[string]any{"issue_type": "story", "points": 3, "stage": "todo", "sprint_id": data.Sprints[0].ID}, nil); c != 200 {
		t.Fatal(c)
	}
	if c := api.do("POST", base+"/sprints/"+data.Sprints[0].ID+"/start", token, map[string]any{}, nil); c != 200 {
		t.Fatal(c)
	}
	if c := api.do("PATCH", base, token, map[string]any{"method": "simple"}, nil); c != 409 {
		t.Fatal("active", c)
	}
	if c := api.do("POST", base+"/sprints/"+data.Sprints[0].ID+"/close", token, map[string]any{}, nil); c != 200 {
		t.Fatal(c)
	}
}
