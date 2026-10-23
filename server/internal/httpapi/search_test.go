package httpapi

import (
	"net/url"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

func TestSearchAndSavedFilterAPI(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("search@example.com")
	bob := api.register("other-search@example.com")
	project := api.createProject(alice, map[string]any{"name": "کار شخصی"})
	secret := api.createTask(bob, "", "ميکنم Secret")
	matching := api.createTask(alice, project.ID, "می‌کنم")
	api.createTask(alice, project.ID, "unrelated")
	hidden := api.createTask(alice, project.ID, "می کنم done")
	api.do("POST", "/api/v1/tasks/"+hidden.ID+"/close", alice, nil, nil)
	path := "/api/v1/search?today=2026-10-21&q=" + url.QueryEscape("ميكنم")
	var page store.SearchPage
	if code := api.do("GET", path, alice, nil, &page); code != 200 || len(page.Tasks) != 1 || page.Tasks[0].ID != matching.ID {
		t.Fatal("Persian normalized search/ownership", code, page, secret.ID)
	}
	if code := api.do("GET", path+"&completed=true", alice, nil, &page); code != 200 || len(page.Tasks) != 2 {
		t.Fatal("completed opt-in", code, page)
	}
	if code := api.do("GET", "/api/v1/search?today=2026-10-21&q="+url.QueryEscape(`#"کار شخصی" & no date`), alice, nil, &page); code != 200 || len(page.Tasks) != 2 {
		t.Fatal("project and date filter", code, page)
	}
	if code := api.do("GET", "/api/v1/search?today=2026-10-21&limit=1", alice, nil, &page); code != 200 || len(page.Tasks) != 1 || !page.HasMore {
		t.Fatal("bounded page", code, page)
	}
	for _, query := range []string{"", "?today=bad", "?today=2026-10-21&q=(", "?today=2026-10-21&sort=forged", "?today=2026-10-21&limit=201", "?today=2026-10-21&offset=-1", "?today=2026-10-21&limit=x", "?today=2026-10-21&completed=forged"} {
		if code := api.do("GET", "/api/v1/search"+query, alice, nil, nil); code != 400 {
			t.Fatal("invalid query", query, code)
		}
	}
	var saved struct {
		Filter store.SavedFilter `json:"filter"`
	}
	input := map[string]any{"name": "کارهای مهم", "query": "p1 | today", "is_favorite": true}
	if code := api.do("POST", "/api/v1/filters", alice, input, &saved); code != 201 || saved.Filter.ID == "" {
		t.Fatal("save", code, saved)
	}
	id := saved.Filter.ID
	for _, method := range []string{"PUT", "DELETE"} {
		if code := api.do(method, "/api/v1/filters/"+id, bob, input, nil); code != 404 {
			t.Fatal("foreign filter", method, code)
		}
	}
	var list struct {
		Filters []store.SavedFilter `json:"filters"`
	}
	if code := api.do("GET", "/api/v1/filters", bob, nil, &list); code != 200 || len(list.Filters) != 0 {
		t.Fatal("foreign filter list", code, list)
	}
	if code := api.do("GET", "/api/v1/filters", alice, nil, &list); code != 200 || len(list.Filters) != 1 || list.Filters[0].ID != id {
		t.Fatal("own filter list", code, list)
	}
	if code := api.do("PUT", "/api/v1/filters/"+id, alice, map[string]any{"name": "edited", "query": "no date", "color": "#123456", "sort": "priority"}, &saved); code != 200 || saved.Filter.Query != "no date" {
		t.Fatal("edit filter", code, saved)
	}
	for _, invalid := range []map[string]any{{"name": "", "query": "today"}, {"name": "x", "query": "("}, {"name": "x", "query": "today", "color": "red"}, {"name": "x", "query": "today", "sort": "forged"}, {"name": "x", "owner_id": "forged"}} {
		if code := api.do("POST", "/api/v1/filters", alice, invalid, nil); code != 400 {
			t.Fatal("invalid filter", code)
		}
	}
	for _, endpoint := range []struct{ method, path string }{{"GET", "/api/v1/search?today=2026-10-21"}, {"GET", "/api/v1/filters"}, {"POST", "/api/v1/filters"}, {"PUT", "/api/v1/filters/" + id}, {"DELETE", "/api/v1/filters/" + id}} {
		if code := api.do(endpoint.method, endpoint.path, "", input, nil); code != 401 {
			t.Fatal("auth", endpoint, code)
		}
	}
	if code := api.do("DELETE", "/api/v1/filters/"+id, alice, nil, nil); code != 204 {
		t.Fatal("delete", code)
	}
	if code := api.do("DELETE", "/api/v1/filters/"+id, alice, nil, nil); code != 404 {
		t.Fatal("deleted id", code)
	}
}
