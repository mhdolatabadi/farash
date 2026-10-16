package httpapi

import (
	"context"
	"errors"
	"github.com/mhdolatabadi/farash/server/internal/store"
	"testing"
	"time"
)

func TestProgressLifecycleAndPrivacy(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("progress@example.com")
	other := api.register("other@example.com")
	get := func(token string) store.Progress {
		t.Helper()
		var p store.Progress
		if code := api.do("GET", "/api/v1/progress?timezone=Asia%2FTehran", token, nil, &p); code != 200 {
			t.Fatalf("progress: %d", code)
		}
		return p
	}
	if p := get(token); p.XP != 0 || p.WeeklyGoal != 3 || p.Level != 1 || len(p.Badges) != 0 {
		t.Fatalf("initial: %+v", p)
	}
	task := api.createTask(token, "", "اولین قدم")
	path := "/api/v1/tasks/" + task.ID
	for range 2 {
		if code := api.do("POST", path+"/close", token, nil, nil); code != 200 {
			t.Fatalf("close: %d", code)
		}
	}
	if p := get(token); p.XP != 10 || p.WeeklyDays != 1 || len(p.Badges) != 1 || p.WeekReport.Completed != 1 {
		t.Fatalf("completion: %+v", p)
	}
	if p := get(other); p.XP != 0 || p.WeeklyDays != 0 || p.WeekReport.Completed != 0 {
		t.Fatalf("private progress leaked: %+v", p)
	}
	if code := api.do("PATCH", "/api/v1/progress", token, map[string]any{"weekly_goal": 1}, nil); code != 200 {
		t.Fatalf("goal: %d", code)
	}
	if p := get(token); p.WeeklyGoal != 1 || len(p.Badges) != 2 {
		t.Fatalf("weekly badge: %+v", p)
	}
	if p := get(other); p.WeeklyGoal != 3 {
		t.Fatal("goal leaked to other account")
	}
	api.do("POST", path+"/reopen", token, nil, nil)
	if p := get(token); p.XP != 0 || p.WeeklyDays != 0 || len(p.Badges) != 0 || p.WeekReport.Completed != 0 {
		t.Fatalf("undo: %+v", p)
	}
	api.do("POST", path+"/close", token, nil, nil)
	api.do("DELETE", path, token, nil, nil)
	if p := get(token); p.XP != 0 {
		t.Fatalf("deleted: %+v", p)
	}
	api.do("POST", path+"/restore", token, nil, nil)
	if p := get(token); p.XP != 10 {
		t.Fatalf("restored: %+v", p)
	}
	for _, goal := range []any{0, 8, -1, 1.5, "3", nil} {
		if code := api.do("PATCH", "/api/v1/progress", token, map[string]any{"weekly_goal": goal}, nil); code != 400 {
			t.Fatalf("invalid goal %v: %d", goal, code)
		}
	}
	for _, method := range []string{"GET", "PATCH"} {
		if code := api.do(method, "/api/v1/progress", "", nil, nil); code != 401 {
			t.Fatalf("unauthenticated: %d", code)
		}
	}
	if code := api.do("GET", "/api/v1/progress?timezone=invalid", token, nil, nil); code != 400 {
		t.Fatalf("timezone: %d", code)
	}
}

// Exercise validation, authentication and failure responses even when the
// integration database is not configured.
type progressUsers struct {
	*fakeUsers
	fail bool
}

func (s *progressUsers) Progress(context.Context, string, time.Time, *time.Location) (store.Progress, error) {
	if s.fail {
		return store.Progress{}, errors.New("unavailable")
	}
	return store.Progress{Level: 1, WeeklyGoal: 3, Badges: []string{}}, nil
}
func (s *progressUsers) SetProgressGoal(context.Context, string, int) error {
	if s.fail {
		return errors.New("unavailable")
	}
	return nil
}
func TestProgressValidationAndFailures(t *testing.T) {
	data := &progressUsers{fakeUsers: newFakeUsers()}
	api := &dbAPI{t: t, handler: NewHandler(Config{Store: data, AuthSecret: []byte("test-secret")})}
	token := api.register("progress-unit@example.com")
	for _, method := range []string{"GET", "PATCH"} {
		if code := api.do(method, "/api/v1/progress", "", nil, nil); code != 401 {
			t.Fatalf("authentication: %d", code)
		}
	}
	for _, body := range []string{`{}`, `{"weekly_goal":0}`, `{"weekly_goal":8}`, `{"weekly_goal":1.5}`, `{"weekly_goal":"3"}`, `{"weekly_goal":3,"owner_id":"someone-else"}`, `null`, `{`} {
		if code := api.do("PATCH", "/api/v1/progress", token, body, nil); code != 400 {
			t.Fatalf("validation %s: %d", body, code)
		}
	}
	for _, zone := range []string{"invalid", "Local"} {
		if code := api.do("GET", "/api/v1/progress?timezone="+zone, token, nil, nil); code != 400 {
			t.Fatalf("zone %s: %d", zone, code)
		}
	}
	data.fail = true
	for _, method := range []string{"GET", "PATCH"} {
		var response map[string]string
		if code := api.do(method, "/api/v1/progress", token, map[string]int{"weekly_goal": 3}, &response); code != 500 || response["error"] != "progress_unavailable" {
			t.Fatalf("failure: %d %v", code, response)
		}
	}
}

func (s *progressUsers) SetWeeklyTaskGoal(ctx context.Context, owner string, target int) error {
	return s.SetProgressGoal(ctx, owner, target)
}

func TestWeeklyChallengeValidation(t *testing.T) {
	data := &progressUsers{fakeUsers: newFakeUsers()}
	api := &dbAPI{t: t, handler: NewHandler(Config{Store: data, AuthSecret: []byte("test-secret")})}
	token := api.register("challenge-unit@example.com")
	const path = "/api/v1/progress/challenge"
	if code := api.do("PATCH", path, "", map[string]int{"target": 10}, nil); code != 401 {
		t.Fatalf("auth: %d", code)
	}
	for _, body := range []string{`{}`, `null`, `{"target":0}`, `{"target":501}`, `{"target":-1}`, `{"target":1.5}`, `{"target":"10"}`, `{"target":10,"owner_id":"other"}`} {
		if code := api.do("PATCH", path, token, body, nil); code != 400 {
			t.Fatalf("invalid %s: %d", body, code)
		}
	}
	for _, target := range []int{1, 10, 500} {
		if code := api.do("PATCH", path, token, map[string]int{"target": target}, nil); code != 200 {
			t.Fatalf("valid: %d", code)
		}
	}
	data.fail = true
	if code := api.do("PATCH", path, token, map[string]int{"target": 10}, nil); code != 500 {
		t.Fatalf("failure: %d", code)
	}
}

func TestWeeklyChallengeOwnerAndUndo(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("challenge@example.com")
	other := api.register("private-challenge@example.com")
	read := func(token string) store.Progress {
		t.Helper()
		var p store.Progress
		if code := api.do("GET", "/api/v1/progress", token, nil, &p); code != 200 {
			t.Fatalf("read: %d", code)
		}
		return p
	}
	if p := read(token); p.WeeklyTaskGoal != 10 {
		t.Fatalf("default: %+v", p)
	}
	task := api.createTask(token, "", "هدف شخصی")
	path := "/api/v1/tasks/" + task.ID
	api.do("POST", path+"/close", token, nil, nil)
	api.do("PATCH", "/api/v1/progress/challenge", token, map[string]int{"target": 1}, nil)
	if p := read(token); p.WeeklyTaskGoal != 1 || p.WeekReport.Completed != 1 || p.XP != 10 || p.WeeklyGoal != 3 {
		t.Fatalf("challenge: %+v", p)
	}
	if p := read(other); p.WeeklyTaskGoal != 10 || p.WeekReport.Completed != 0 {
		t.Fatalf("privacy: %+v", p)
	}
	api.do("PATCH", "/api/v1/progress", token, map[string]int{"weekly_goal": 5}, nil)
	if p := read(token); p.WeeklyTaskGoal != 1 || p.WeeklyGoal != 5 {
		t.Fatalf("independent goals: %+v", p)
	}
	api.do("POST", path+"/reopen", token, nil, nil)
	if p := read(token); p.WeekReport.Completed != 0 || p.XP != 0 || p.WeeklyTaskGoal != 1 {
		t.Fatalf("undo: %+v", p)
	}
	api.do("POST", path+"/close", token, nil, nil)
	api.do("DELETE", path, token, nil, nil)
	if p := read(token); p.WeekReport.Completed != 0 || p.WeeklyTaskGoal != 1 {
		t.Fatalf("delete: %+v", p)
	}
}
