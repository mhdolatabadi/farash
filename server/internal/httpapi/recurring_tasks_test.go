package httpapi

import "testing"

func TestRecurringTasksAPI(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("recurring-api@example.com")
	other := api.register("recurring-private@example.com")
	p := api.createProject(token, map[string]any{"name": "Routine"})
	task := api.createTask(token, p.ID, "Read")
	base := "/api/v1/tasks/" + task.ID + "/recurrence"
	for _, route := range []struct{ method, path string }{{"GET", base}, {"PUT", base}, {"POST", base + "/skip"}, {"POST", base + "/undo"}} {
		if code := api.do(route.method, route.path, "", map[string]any{}, nil); code != 401 {
			t.Fatal("auth", route, code)
		}
		if code := api.do(route.method, route.path, other, map[string]any{}, nil); code != 404 {
			t.Fatal("private", route, code)
		}
	}
	body := map[string]any{"schedule": map[string]any{"start": "2026-10-22", "timezone": "Asia/Tehran", "rule": map[string]any{"frequency": "day", "interval": 1, "calendar": "jalali", "basis": "due", "count": 2}}}
	if code := api.do("PUT", base, token, body, nil); code != 400 {
		t.Fatal("undated", code)
	}
	if code := api.do("PATCH", "/api/v1/tasks/"+task.ID, token, map[string]any{"due": map[string]any{"date": "2026-10-22"}}, nil); code != 200 {
		t.Fatal(code)
	}
	if code := api.do("PUT", base, token, body, nil); code != 200 {
		t.Fatal(code)
	}
	if code := api.do("POST", base+"/skip", token, map[string]any{}, nil); code != 200 {
		t.Fatal(code)
	}
	if code := api.do("POST", base+"/undo", token, map[string]any{}, nil); code != 200 {
		t.Fatal(code)
	}
	if code := api.do("PUT", base, token, map[string]any{"schedule": nil}, nil); code != 200 {
		t.Fatal(code)
	}
}
