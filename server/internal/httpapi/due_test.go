package httpapi

import (
	"net/http"
	"testing"
	"time"
)

func TestDueDatesLifecycle(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")

	// All-day due and a deadline on create.
	var created oneTask
	if code := api.do("POST", "/api/v1/tasks", token, map[string]any{
		"title": "Report", "due": map[string]any{"date": "2026-10-05"}, "deadline": "2026-10-10",
	}, &created); code != http.StatusCreated || created.Task.Due == nil || created.Task.Due.Date != "2026-10-05" ||
		created.Task.Due.Datetime != nil || created.Task.Deadline == nil || *created.Task.Deadline != "2026-10-10" {
		t.Fatalf("create: %d %+v", code, created.Task)
	}
	path := "/api/v1/tasks/" + created.Task.ID

	// A time in Tehran: stored in UTC, dated in Tehran (00:30 local is the
	// previous day in UTC).
	var edited oneTask
	if code := api.do("PATCH", path, token, map[string]any{
		"due":              map[string]any{"datetime": "2026-10-05T21:00:00Z", "timezone": "Asia/Tehran"},
		"duration_minutes": 45,
	}, &edited); code != http.StatusOK {
		t.Fatalf("set time: %d", code)
	}
	due := edited.Task.Due
	if due == nil || due.Date != "2026-10-06" || due.Datetime == nil || !due.Datetime.Equal(time.Date(2026, 10, 5, 21, 0, 0, 0, time.UTC)) ||
		due.Timezone == nil || *due.Timezone != "Asia/Tehran" || edited.Task.DurationMinutes == nil || *edited.Task.DurationMinutes != 45 {
		t.Fatalf("timed due: %+v", edited.Task)
	}

	// Editing something else keeps all of it.
	api.do("PATCH", path, token, map[string]any{"title": "Final report"}, &edited)
	if edited.Task.Due == nil || edited.Task.Due.Datetime == nil || edited.Task.DurationMinutes == nil || edited.Task.Deadline == nil {
		t.Fatalf("plain edit lost dates: %+v", edited.Task)
	}

	// Back to all-day drops the duration; null clears due and deadline.
	api.do("PATCH", path, token, map[string]any{"due": map[string]any{"date": "2026-10-07"}}, &edited)
	if edited.Task.Due.Datetime != nil || edited.Task.Due.Timezone != nil || edited.Task.DurationMinutes != nil {
		t.Fatalf("all-day: %+v", edited.Task)
	}
	api.do("PATCH", path, token, map[string]any{"due": nil, "deadline": nil}, &edited)
	if edited.Task.Due != nil || edited.Task.Deadline != nil {
		t.Fatalf("clear: %+v", edited.Task)
	}
}

func TestDueValidation(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	task := api.createTask(token, "", "x")
	path := "/api/v1/tasks/" + task.ID
	cases := []struct {
		name string
		body map[string]any
		code string
	}{
		{"bad date", map[string]any{"due": map[string]any{"date": "2026-13-01"}}, "invalid_due"},
		{"empty due", map[string]any{"due": map[string]any{}}, "invalid_due"},
		{"far year", map[string]any{"due": map[string]any{"date": "2400-01-01"}}, "invalid_due"},
		{"time without zone", map[string]any{"due": map[string]any{"datetime": "2026-10-05T10:00:00Z"}}, "invalid_due"},
		{"unknown zone", map[string]any{"due": map[string]any{"datetime": "2026-10-05T10:00:00Z", "timezone": "Mars/Base"}}, "invalid_due"},
		{"local zone", map[string]any{"due": map[string]any{"datetime": "2026-10-05T10:00:00Z", "timezone": "Local"}}, "invalid_due"},
		{"bad datetime", map[string]any{"due": map[string]any{"datetime": "tomorrow", "timezone": "UTC"}}, "invalid_due"},
		{"date not the local day", map[string]any{"due": map[string]any{"date": "2026-10-05", "datetime": "2026-10-05T21:00:00Z", "timezone": "Asia/Tehran"}}, "invalid_due"},
		{"bad deadline", map[string]any{"deadline": "soon"}, "invalid_deadline"},
		{"duration without time", map[string]any{"due": map[string]any{"date": "2026-10-05"}, "duration_minutes": 30}, "invalid_duration"},
		{"duration too long", map[string]any{"due": map[string]any{"datetime": "2026-10-05T10:00:00Z", "timezone": "UTC"}, "duration_minutes": 1441}, "invalid_duration"},
		{"duration zero", map[string]any{"due": map[string]any{"datetime": "2026-10-05T10:00:00Z", "timezone": "UTC"}, "duration_minutes": 0}, "invalid_duration"},
	}
	for _, c := range cases {
		var failure apiError
		if code := api.do("PATCH", path, token, c.body, &failure); code != http.StatusBadRequest || failure.Error != c.code {
			t.Fatalf("%s: %d %+v", c.name, code, failure)
		}
		failure = apiError{}
		create := map[string]any{"title": "y"}
		for k, v := range c.body {
			create[k] = v
		}
		if code := api.do("POST", "/api/v1/tasks", token, create, &failure); code != http.StatusBadRequest || failure.Error != c.code {
			t.Fatalf("create %s: %d %+v", c.name, code, failure)
		}
	}
	var failure apiError
	if code := api.do("PATCH", path, token, map[string]any{"due": map[string]any{"date": "2026-10-05", "when": "now"}}, &failure); code != http.StatusBadRequest || failure.Error != "invalid_json" {
		t.Fatalf("unknown due field: %d %+v", code, failure)
	}
}

func TestRescheduleMany(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	other := api.register("b@example.com")
	a := api.createTask(token, "", "A")
	b := api.createTask(token, "", "B")
	foreign := api.createTask(other, "", "Theirs")

	var timed oneTask
	api.do("PATCH", "/api/v1/tasks/"+a.ID, token, map[string]any{
		"due":              map[string]any{"datetime": "2026-10-05T06:30:00Z", "timezone": "Asia/Tehran"},
		"duration_minutes": 30, "priority": 1,
	}, &timed)

	var result taskList
	if code := api.do("POST", "/api/v1/tasks/reschedule", token, map[string]any{
		"task_ids": []string{b.ID, a.ID}, "due": map[string]any{"date": "2026-10-09"},
	}, &result); code != http.StatusOK || len(result.Tasks) != 2 || result.Tasks[0].ID != b.ID {
		t.Fatalf("reschedule: %d %+v", code, result)
	}
	for _, task := range result.Tasks {
		if task.Due == nil || task.Due.Date != "2026-10-09" || task.DurationMinutes != nil {
			t.Fatalf("rescheduled task: %+v", task)
		}
	}
	if result.Tasks[1].Priority != 1 || result.Tasks[1].Title != "A" {
		t.Fatalf("other fields changed: %+v", result.Tasks[1])
	}

	// A timed due keeps an existing duration; null removes the dates.
	api.do("PATCH", "/api/v1/tasks/"+a.ID, token, map[string]any{
		"due": map[string]any{"datetime": "2026-10-05T06:30:00Z", "timezone": "UTC"}, "duration_minutes": 20,
	}, nil)
	api.do("POST", "/api/v1/tasks/reschedule", token, map[string]any{
		"task_ids": []string{a.ID}, "due": map[string]any{"datetime": "2026-10-06T06:30:00Z", "timezone": "UTC"},
	}, &result)
	if d := result.Tasks[0].DurationMinutes; d == nil || *d != 20 {
		t.Fatalf("duration lost: %+v", result.Tasks[0])
	}
	api.do("POST", "/api/v1/tasks/reschedule", token, map[string]any{"task_ids": []string{a.ID, b.ID}, "due": nil}, &result)
	if result.Tasks[0].Due != nil || result.Tasks[1].Due != nil {
		t.Fatalf("clear: %+v", result.Tasks)
	}

	// All or nothing: another user's task answers 404 and nothing changes.
	var failure apiError
	if code := api.do("POST", "/api/v1/tasks/reschedule", token, map[string]any{
		"task_ids": []string{a.ID, foreign.ID}, "due": map[string]any{"date": "2026-11-01"},
	}, &failure); code != http.StatusNotFound || failure.Error != "task_not_found" {
		t.Fatalf("foreign task: %d %+v", code, failure)
	}
	var list taskList
	api.do("GET", "/api/v1/tasks?projectId="+a.ProjectID, token, nil, &list)
	for _, task := range list.Tasks {
		if task.Due != nil {
			t.Fatalf("partial reschedule: %+v", task)
		}
	}
	for name, body := range map[string]map[string]any{
		"no ids":    {"task_ids": []string{}, "due": nil},
		"duplicate": {"task_ids": []string{a.ID, a.ID}, "due": nil},
	} {
		failure = apiError{}
		if code := api.do("POST", "/api/v1/tasks/reschedule", token, body, &failure); code != http.StatusBadRequest || failure.Error != "invalid_task_ids" {
			t.Fatalf("%s: %d %+v", name, code, failure)
		}
	}
	failure = apiError{}
	if code := api.do("POST", "/api/v1/tasks/reschedule", token, map[string]any{"task_ids": []string{a.ID}, "due": map[string]any{"date": "x"}}, &failure); code != http.StatusBadRequest || failure.Error != "invalid_due" {
		t.Fatalf("bad due: %d %+v", code, failure)
	}
	if code := api.do("POST", "/api/v1/tasks/reschedule", "", map[string]any{"task_ids": []string{a.ID}}, nil); code != http.StatusUnauthorized {
		t.Fatalf("anonymous: %d", code)
	}
}
