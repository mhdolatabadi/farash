package httpapi

import (
	"github.com/mhdolatabadi/farash/server/internal/store"
	"testing"
	"time"
)

func TestTimeAPI(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("time-api@example.com")
	other := api.register("time-other@example.com")
	task := api.createTask(token, "", "work")
	for _, route := range []struct{ method, path string }{{"GET", "/api/v1/time"}, {"POST", "/api/v1/time"}, {"POST", "/api/v1/time/id/stop"}, {"PATCH", "/api/v1/time/id"}, {"DELETE", "/api/v1/time/id"}} {
		if code := api.do(route.method, route.path, "", nil, nil); code != 401 {
			t.Fatalf("auth %s %d", route.path, code)
		}
	}
	var entry store.TimeEntry
	body := map[string]any{"task_id": task.ID, "source": "timer", "request_key": "start-test-key"}
	if code := api.do("POST", "/api/v1/time", token, body, &entry); code != 200 {
		t.Fatal("start", code)
	}
	if code := api.do("POST", "/api/v1/time/"+entry.ID+"/stop", other, nil, nil); code != 404 {
		t.Fatal("privacy", code)
	}
	body["request_key"] = "other-start-key"
	if code := api.do("POST", "/api/v1/time", token, body, nil); code != 409 {
		t.Fatal("running", code)
	}
	if code := api.do("POST", "/api/v1/time/"+entry.ID+"/stop", token, nil, nil); code != 200 {
		t.Fatal("stop", code)
	}
	for _, query := range []string{"?timezone=invalid", "?timezone=Local", "?from=bad&to=bad", "?from=2026-01-01T00:00:00Z&to=2027-01-01T00:00:00Z"} {
		if code := api.do("GET", "/api/v1/time"+query, token, nil, nil); code != 400 {
			t.Fatal(query, code)
		}
	}
	for _, body := range []map[string]any{
		{"source": "timer", "task_id": task.ID, "request_key": "a"},
		{"source": "focus", "task_id": task.ID, "request_key": "invalid-focus-key", "focus_seconds": 4000},
		{"source": "manual", "task_id": task.ID, "request_key": "manual-bad-key", "started_at": time.Now(), "ended_at": time.Now().Add(30 * time.Hour)},
	} {
		if code := api.do("POST", "/api/v1/time", token, body, nil); code != 400 {
			t.Fatal("validation", code)
		}
	}
	if code := api.do("GET", "/api/v1/time?taskId="+task.ID, other, nil, nil); code != 404 {
		t.Fatal("private task report", code)
	}
	var report store.TimeReport
	if code := api.do("GET", "/api/v1/time?timezone=Asia%2FTehran", token, nil, &report); code != 200 || len(report.Entries) != 1 {
		t.Fatalf("report %d %+v", code, report)
	}
}
