package httpapi

import (
	"github.com/mhdolatabadi/farash/server/internal/store"
	"testing"
)

func TestCommentsAPI(t *testing.T) {
	api := newDBAPI(t)
	owner := api.register("comment-api@example.com")
	outsider := api.register("comment-other@example.com")
	project := api.createProject(owner, map[string]any{"name": "Private"})
	task := api.createTask(owner, project.ID, "Read")
	for _, base := range []string{"/api/v1/tasks/" + task.ID + "/comments", "/api/v1/projects/" + project.ID + "/comments"} {
		for _, route := range []struct{ method, suffix string }{{"GET", ""}, {"POST", ""}, {"PATCH", "/secret"}, {"DELETE", "/secret"}} {
			in := map[string]any{"body": "private text", "request_key": "privacy-request"}
			if code := api.do(route.method, base+route.suffix, "", in, nil); code != 401 {
				t.Fatal("auth", route, code)
			}
			if code := api.do(route.method, base+route.suffix, outsider, in, nil); code != 404 {
				t.Fatal("privacy", route, code)
			}
		}
	}
	base := "/api/v1/tasks/" + task.ID + "/comments"
	if code := api.do("POST", base, owner, map[string]any{"body": " ", "request_key": "valid-request"}, nil); code != 400 {
		t.Fatal("validation", code)
	}
	var created store.Comment
	input := map[string]any{"body": "**متن**", "request_key": "comment-request"}
	if code := api.do("POST", base, owner, input, &created); code != 200 || created.ID == "" {
		t.Fatal("create", code, created)
	}
	var retry store.Comment
	if code := api.do("POST", base, owner, input, &retry); code != 200 || retry.ID != created.ID {
		t.Fatal("retry", code, retry)
	}
	var page store.CommentPage
	if code := api.do("GET", base, owner, nil, &page); code != 200 || page.Total != 1 || len(page.Comments) != 1 {
		t.Fatal("list", code, page)
	}
	if code := api.do("GET", base+"?after=other-cursor", owner, nil, nil); code != 400 {
		t.Fatal("cursor", code)
	}
	if code := api.do("PATCH", base+"/"+created.ID, owner, map[string]any{"body": "updated"}, &retry); code != 200 || retry.Body != "updated" {
		t.Fatal("edit", code, retry)
	}
	if code := api.do("DELETE", base+"/"+created.ID, owner, nil, &retry); code != 200 || retry.DeletedAt == nil || retry.Body != "" {
		t.Fatal("delete", code, retry)
	}
	for i := 0; i < 30; i++ {
		api.do("POST", base, owner, map[string]any{"body": "", "request_key": "throttled-request"}, nil)
	}
	if code := api.do("POST", base, owner, input, nil); code != 429 {
		t.Fatal("throttle", code)
	}
}
