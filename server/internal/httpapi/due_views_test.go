package httpapi

import (
	"net/http"
	"testing"
)

func TestDueViews(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("a@example.com")
	bob := api.register("b@example.com")
	work := api.createProject(alice, map[string]any{"name": "Work"})
	archived := api.createProject(alice, map[string]any{"name": "Old"})

	dated := func(token, project, title, date string) string {
		var created oneTask
		if code := api.do("POST", "/api/v1/tasks", token, map[string]any{
			"title": title, "project_id": project, "due": map[string]any{"date": date},
		}, &created); code != http.StatusCreated {
			t.Fatalf("create %s: %d", title, code)
		}
		return created.Task.ID
	}
	dated(alice, "", "late", "2026-10-01")
	dated(alice, work.ID, "today", "2026-10-08")
	dated(alice, work.ID, "soon", "2026-10-10")
	dated(alice, work.ID, "later", "2026-11-20")
	done := dated(alice, work.ID, "done", "2026-10-08")
	api.do("POST", "/api/v1/tasks/"+done+"/close", alice, nil, nil)
	dated(alice, archived.ID, "hidden", "2026-10-08")
	api.do("PATCH", "/api/v1/projects/"+archived.ID, alice, map[string]any{"is_archived": true}, nil)
	api.createTask(alice, "", "undated")
	dated(bob, "", "bob's", "2026-10-08")

	titles := func(query string) []string {
		t.Helper()
		var list taskList
		if code := api.do("GET", "/api/v1/tasks?"+query, alice, nil, &list); code != http.StatusOK {
			t.Fatalf("%s: %d", query, code)
		}
		out := []string{}
		for _, task := range list.Tasks {
			out = append(out, task.Title)
		}
		return out
	}
	expect := func(query string, want ...string) {
		t.Helper()
		got := titles(query)
		if len(got) != len(want) {
			t.Fatalf("%s: got %v want %v", query, got, want)
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("%s: got %v want %v", query, got, want)
			}
		}
	}
	// Today, overdue (no lower bound), and upcoming, open tasks only.
	expect("from=2026-10-08&to=2026-10-08", "today")
	expect("to=2026-10-07", "late")
	expect("from=2026-10-09&to=2026-10-22", "soon")
	expect("to=2026-12-31", "late", "today", "soon", "later")

	var failure apiError
	for _, query := range []string{"to=", "to=2026-13-01", "from=2026-10-09&to=2026-10-01", "from=2026-01-01&to=2027-06-01"} {
		failure = apiError{}
		if code := api.do("GET", "/api/v1/tasks?"+query, alice, nil, &failure); code != http.StatusBadRequest || failure.Error != "invalid_due_range" {
			t.Fatalf("%s: %d %+v", query, code, failure)
		}
	}
	if code := api.do("GET", "/api/v1/tasks?to=2026-10-08", "", nil, nil); code != http.StatusUnauthorized {
		t.Fatalf("anonymous: %d", code)
	}
}
