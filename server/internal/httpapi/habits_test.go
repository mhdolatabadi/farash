package httpapi

import (
	"fmt"
	"testing"
	"time"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

func TestHabitsAPI(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("habits@example.com")
	other := api.register("habits-other@example.com")
	for _, route := range []struct{ method, path string }{
		{"GET", "/api/v1/habits"}, {"POST", "/api/v1/habits"}, {"POST", "/api/v1/habits/reorder"},
		{"PATCH", "/api/v1/habits/id"}, {"DELETE", "/api/v1/habits/id"},
		{"PUT", "/api/v1/habits/id/entries/2026-01-01"}, {"DELETE", "/api/v1/habits/id/entries/2026-01-01"},
	} {
		if code := api.do(route.method, route.path, "", nil, nil); code != 401 {
			t.Fatalf("auth %s %s %d", route.method, route.path, code)
		}
	}
	for _, body := range []map[string]any{
		{},
		{"name": "  "},
		{"name": "x", "color": 20},
		{"name": "x", "freq_num": 4, "freq_den": 3},
		{"name": "x", "freq_den": 400},
		{"name": "x", "kind": "count"},
		{"name": "x", "kind": "numeric"},
		{"name": "x", "kind": "numeric", "target_value": -1},
		{"name": "x", "extra": true},
	} {
		if code := api.do("POST", "/api/v1/habits", token, body, nil); code != 400 {
			t.Fatalf("validation %v %d", body, code)
		}
	}
	var created struct{ Habit store.Habit }
	if code := api.do("POST", "/api/v1/habits", token, map[string]any{"name": "ورزش", "question": "امروز ورزش کردی؟", "freq_num": 3, "freq_den": 7}, &created); code != 201 {
		t.Fatal("create", code)
	}
	h := created.Habit
	if h.Kind != "boolean" || h.FreqNum != 3 || h.FreqDen != 7 || h.Color != 8 || len(h.Entries) != 0 {
		t.Fatalf("defaults %+v", h)
	}
	var water struct{ Habit store.Habit }
	if code := api.do("POST", "/api/v1/habits", token, map[string]any{"name": "آب", "kind": "numeric", "target_value": 8, "unit": "لیوان"}, &water); code != 201 || water.Habit.SortOrder != 1 {
		t.Fatal("create numeric", code, water.Habit.SortOrder)
	}
	today := time.Now().UTC().Format(time.DateOnly)
	entry := func(id string) string { return "/api/v1/habits/" + id + "/entries/" + today }
	if code := api.do("PUT", entry(h.ID), other, map[string]any{"value": 1}, nil); code != 404 {
		t.Fatal("private entry", code)
	}
	for _, body := range []map[string]any{{"value": 2}, {"value": -1}} {
		if code := api.do("PUT", entry(h.ID), token, body, nil); code != 400 {
			t.Fatal("entry validation", body, code)
		}
	}
	future := time.Now().UTC().AddDate(0, 0, 3).Format(time.DateOnly)
	for _, day := range []string{future, "1999-12-31", "2026-13-01", "today"} {
		if code := api.do("PUT", "/api/v1/habits/"+h.ID+"/entries/"+day, token, map[string]any{"value": 1}, nil); code != 400 {
			t.Fatal("day validation", day, code)
		}
	}
	var saved struct{ Entry store.HabitEntry }
	if code := api.do("PUT", entry(h.ID), token, map[string]any{"value": 1}, &saved); code != 200 || saved.Entry.Day != today || saved.Entry.Value != 1 {
		t.Fatalf("entry %d %+v", code, saved)
	}
	if code := api.do("PUT", entry(h.ID), token, map[string]any{"value": 1, "skip": true}, &saved); code != 200 || !saved.Entry.Skip || saved.Entry.Value != 0 {
		t.Fatalf("skip %d %+v", code, saved)
	}
	if code := api.do("PUT", entry(water.Habit.ID), token, map[string]any{"value": 5.5}, nil); code != 200 {
		t.Fatal("numeric entry", code)
	}
	var list struct{ Habits []store.Habit }
	if code := api.do("GET", "/api/v1/habits", other, nil, &list); code != 200 || len(list.Habits) != 0 {
		t.Fatal("private list", code, len(list.Habits))
	}
	if code := api.do("GET", "/api/v1/habits", token, nil, &list); code != 200 || len(list.Habits) != 2 || len(list.Habits[0].Entries) != 1 || list.Habits[1].Entries[0].Value != 5.5 {
		t.Fatalf("list %d %+v", code, list)
	}
	if code := api.do("DELETE", entry(h.ID), other, nil, nil); code != 404 {
		t.Fatal("private clear", code)
	}
	if code := api.do("DELETE", entry(h.ID), token, nil, nil); code != 200 {
		t.Fatal("clear", code)
	}
	if code := api.do("DELETE", entry(h.ID), token, nil, nil); code != 200 {
		t.Fatal("clear unknown", code)
	}
	var updated struct{ Habit store.Habit }
	if code := api.do("PATCH", "/api/v1/habits/"+h.ID, other, map[string]any{"name": "x"}, nil); code != 404 {
		t.Fatal("private update", code)
	}
	if code := api.do("PATCH", "/api/v1/habits/"+h.ID, token, map[string]any{"kind": "numeric"}, nil); code != 400 {
		t.Fatal("kind is fixed", code)
	}
	if code := api.do("PATCH", "/api/v1/habits/"+h.ID, token, map[string]any{"archived": true, "color": 3}, &updated); code != 200 || !updated.Habit.Archived || updated.Habit.Color != 3 || updated.Habit.Name != "ورزش" {
		t.Fatalf("archive %d %+v", code, updated)
	}
	if code := api.do("POST", "/api/v1/habits/reorder", token, map[string]any{"habit_ids": []string{water.Habit.ID, h.ID}}, nil); code != 200 {
		t.Fatal("reorder", code)
	}
	if code := api.do("POST", "/api/v1/habits/reorder", other, map[string]any{"habit_ids": []string{h.ID}}, nil); code != 404 {
		t.Fatal("private reorder", code)
	}
	if code := api.do("POST", "/api/v1/habits/reorder", token, map[string]any{"habit_ids": []string{h.ID, h.ID}}, nil); code != 400 {
		t.Fatal("duplicate reorder", code)
	}
	api.do("GET", "/api/v1/habits", token, nil, &list)
	if list.Habits[0].ID != water.Habit.ID {
		t.Fatal("order", list.Habits[0].Name)
	}
	if code := api.do("DELETE", "/api/v1/habits/"+h.ID, other, nil, nil); code != 404 {
		t.Fatal("private delete", code)
	}
	if code := api.do("DELETE", "/api/v1/habits/"+h.ID, token, nil, nil); code != 200 {
		t.Fatal("delete", code)
	}
	if code := api.do("PUT", entry(h.ID), token, map[string]any{"value": 1}, nil); code != 404 {
		t.Fatal("deleted habit entry", code)
	}
}

func TestHabitLimit(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("habit-limit@example.com")
	for i := range store.MaxHabits {
		if code := api.do("POST", "/api/v1/habits", token, map[string]any{"name": fmt.Sprint("h", i)}, nil); code != 201 {
			t.Fatal("create", i, code)
		}
	}
	if code := api.do("POST", "/api/v1/habits", token, map[string]any{"name": "one more"}, nil); code != 409 {
		t.Fatal("limit", code)
	}
}
