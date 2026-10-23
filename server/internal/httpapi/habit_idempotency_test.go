package httpapi

import (
	"github.com/mhdolatabadi/farash/server/internal/store"
	"sync"
	"testing"
)

func TestHabitCreateRequestIdentity(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("retry-habit@example.com")
	other := api.register("retry-other@example.com")
	body := map[string]any{"name": " مطالعه ", "request_key": "habit-create-retry-001"}
	var first, retry, foreign struct{ Habit store.Habit }
	if code := api.do("POST", "/api/v1/habits", token, body, &first); code != 201 {
		t.Fatal(code)
	}
	// Discarded/lost first response: the same normalized payload recovers its ID.
	body["name"] = "مطالعه"
	if code := api.do("POST", "/api/v1/habits", token, body, &retry); code != 201 || retry.Habit.ID != first.Habit.ID {
		t.Fatal("retry", code, retry.Habit.ID)
	}
	body["name"] = "different"
	var failure map[string]any
	if code := api.do("POST", "/api/v1/habits", token, body, &failure); code != 409 {
		t.Fatal("mismatch", code)
	}
	if code := api.do("POST", "/api/v1/habits", other, body, &foreign); code != 201 || foreign.Habit.ID == first.Habit.ID {
		t.Fatal("owner isolation", code)
	}
	// A completed retry remains safe even after the object is deleted.
	if code := api.do("DELETE", "/api/v1/habits/"+first.Habit.ID, token, nil, nil); code != 200 {
		t.Fatal(code)
	}
	body["name"] = "مطالعه"
	if code := api.do("POST", "/api/v1/habits", token, body, &retry); code != 201 || retry.Habit.ID != first.Habit.ID {
		t.Fatal("deleted retry", code)
	}
	var listed struct{ Habits []store.Habit }
	api.do("GET", "/api/v1/habits", token, nil, &listed)
	if len(listed.Habits) != 0 {
		t.Fatal("retry resurrected deleted habit")
	}
	for _, key := range []string{"short", "invalid key with spaces-1234"} {
		if code := api.do("POST", "/api/v1/habits", token, map[string]any{"name": "x", "request_key": key}, nil); code != 400 {
			t.Fatal("key validation", code)
		}
	}
}

func TestConcurrentHabitCreateRequest(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("habit-concurrent@example.com")
	const n = 8
	var wg sync.WaitGroup
	ids := make(chan string, n)
	for range n {
		wg.Add(1)
		go func() {
			defer wg.Done()
			var result struct{ Habit store.Habit }
			code := api.do("POST", "/api/v1/habits", token, map[string]any{"name": "walk", "request_key": "parallel-habit-create-001"}, &result)
			if code != 201 {
				t.Errorf("create %d", code)
			}
			ids <- result.Habit.ID
		}()
	}
	wg.Wait()
	close(ids)
	var wanted string
	for id := range ids {
		if wanted == "" {
			wanted = id
		}
		if id != wanted {
			t.Fatal("duplicate IDs")
		}
	}
	var listed struct{ Habits []store.Habit }
	api.do("GET", "/api/v1/habits", token, nil, &listed)
	if len(listed.Habits) != 1 {
		t.Fatal("created", len(listed.Habits))
	}
}
