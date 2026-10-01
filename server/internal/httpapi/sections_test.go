package httpapi

import (
	"net/http"
	"testing"

	"github.com/mhdolatabadi/farash/server/internal/store"
)

type oneSection struct {
	Section store.Section `json:"section"`
}

type sectionList struct {
	Sections []store.Section `json:"sections"`
}

func (a *dbAPI) createSection(token, project, name string) store.Section {
	a.t.Helper()
	var result oneSection
	if code := a.do("POST", "/api/v1/sections", token, map[string]any{"project_id": project, "name": name}, &result); code != http.StatusCreated {
		a.t.Fatalf("create section %q: %d", name, code)
	}
	return result.Section
}

func (a *dbAPI) sectionNames(token, project string) []string {
	a.t.Helper()
	var list sectionList
	if code := a.do("GET", "/api/v1/sections?projectId="+project, token, nil, &list); code != http.StatusOK {
		a.t.Fatalf("list sections: %d", code)
	}
	names := make([]string, len(list.Sections))
	for i, s := range list.Sections {
		names[i] = s.Name
	}
	return names
}

func sameStrings(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestSectionsLifecycle(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	project := api.createProject(token, map[string]any{"name": "Work"})

	todo := api.createSection(token, project.ID, "  برای انجام ")
	doing := api.createSection(token, project.ID, "در حال انجام")
	if todo.Name != "برای انجام" || todo.SortOrder != 0 || doing.SortOrder != 1 {
		t.Fatalf("created: %+v %+v", todo, doing)
	}
	if got := api.sectionNames(token, project.ID); !sameStrings(got, []string{"برای انجام", "در حال انجام"}) {
		t.Fatalf("names = %v", got)
	}

	var updated oneSection
	if code := api.do("PATCH", "/api/v1/sections/"+todo.ID, token,
		map[string]any{"name": "انجام نشده", "is_collapsed": true}, &updated); code != http.StatusOK ||
		updated.Section.Name != "انجام نشده" || !updated.Section.IsCollapsed {
		t.Fatalf("update: %d %+v", code, updated.Section)
	}

	if code := api.do("POST", "/api/v1/sections/reorder", token,
		map[string]any{"project_id": project.ID, "section_ids": []string{doing.ID, todo.ID}}, nil); code != http.StatusNoContent {
		t.Fatalf("reorder: %d", code)
	}
	if got := api.sectionNames(token, project.ID); !sameStrings(got, []string{"در حال انجام", "انجام نشده"}) {
		t.Fatalf("after reorder = %v", got)
	}
}

func TestTasksInSections(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	work := api.createProject(token, map[string]any{"name": "Work"})
	home := api.createProject(token, map[string]any{"name": "Home"})
	section := api.createSection(token, work.ID, "Backlog")
	homeSection := api.createSection(token, home.ID, "Weekend")

	// A section is enough to place the task; its project comes with it.
	var created oneTask
	if code := api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "A", "section_id": section.ID}, &created); code != http.StatusCreated ||
		created.Task.ProjectID != work.ID || created.Task.SectionID == nil || *created.Task.SectionID != section.ID {
		t.Fatalf("create in section: %d %+v", code, created.Task)
	}
	path := "/api/v1/tasks/" + created.Task.ID

	var failure apiError
	if code := api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "B", "project_id": home.ID, "section_id": section.ID}, &failure); code != http.StatusBadRequest || failure.Error != "invalid_section" {
		t.Fatalf("section of another project: %d %+v", code, failure)
	}
	if code := api.do("PATCH", path, token, map[string]any{"section_id": homeSection.ID}, &failure); code != http.StatusBadRequest || failure.Error != "invalid_section" {
		t.Fatalf("move into another project's section: %d %+v", code, failure)
	}

	// Out of the section, then into another project together with its section.
	var edited oneTask
	if code := api.do("PATCH", path, token, map[string]any{"section_id": ""}, &edited); code != http.StatusOK || edited.Task.SectionID != nil {
		t.Fatalf("leave section: %d %+v", code, edited.Task)
	}
	if code := api.do("PATCH", path, token, map[string]any{"project_id": home.ID, "section_id": homeSection.ID}, &edited); code != http.StatusOK ||
		edited.Task.ProjectID != home.ID || edited.Task.SectionID == nil || *edited.Task.SectionID != homeSection.ID {
		t.Fatalf("move with section: %d %+v", code, edited.Task)
	}
	// Moving project without a section drops the old one.
	if code := api.do("PATCH", path, token, map[string]any{"project_id": work.ID}, &edited); code != http.StatusOK || edited.Task.SectionID != nil {
		t.Fatalf("move without section: %d %+v", code, edited.Task)
	}
}

func TestDeletingSections(t *testing.T) {
	api := newDBAPI(t)
	token := api.register("a@example.com")
	project := api.createProject(token, map[string]any{"name": "Work"})
	keep := api.createSection(token, project.ID, "Keep tasks")
	drop := api.createSection(token, project.ID, "Drop tasks")

	var kept, dropped oneTask
	api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "Kept", "section_id": keep.ID}, &kept)
	api.do("POST", "/api/v1/tasks", token, map[string]any{"title": "Dropped", "section_id": drop.ID}, &dropped)

	if code := api.do("DELETE", "/api/v1/sections/"+keep.ID, token, nil, nil); code != http.StatusNoContent {
		t.Fatalf("delete keeping tasks: %d", code)
	}
	if code := api.do("DELETE", "/api/v1/sections/"+drop.ID+"?deleteTasks=true", token, nil, nil); code != http.StatusNoContent {
		t.Fatalf("delete with tasks: %d", code)
	}

	var list taskList
	api.do("GET", "/api/v1/tasks?projectId="+project.ID, token, nil, &list)
	if len(list.Tasks) != 1 || list.Tasks[0].Title != "Kept" || list.Tasks[0].SectionID != nil {
		t.Fatalf("tasks after delete = %+v", list.Tasks)
	}
	// The deleted task can still be restored, without its section.
	var restored oneTask
	if code := api.do("POST", "/api/v1/tasks/"+dropped.Task.ID+"/restore", token, nil, &restored); code != http.StatusOK || restored.Task.SectionID != nil {
		t.Fatalf("restore: %d %+v", code, restored.Task)
	}
	if got := api.sectionNames(token, project.ID); len(got) != 0 {
		t.Fatalf("sections left = %v", got)
	}

	// Deleting the project removes its sections.
	other := api.createSection(token, project.ID, "Gone with project")
	api.do("DELETE", "/api/v1/projects/"+project.ID, token, nil, nil)
	if code := api.do("PATCH", "/api/v1/sections/"+other.ID, token, map[string]any{"name": "x"}, nil); code != http.StatusNotFound {
		t.Fatalf("section of deleted project: %d", code)
	}
}

func TestSectionsValidationAndOwnership(t *testing.T) {
	api := newDBAPI(t)
	alice := api.register("alice@example.com")
	bob := api.register("bob@example.com")
	project := api.createProject(alice, map[string]any{"name": "Private"})
	folder := api.createProject(alice, map[string]any{"name": "Folder", "kind": "folder"})
	section := api.createSection(alice, project.ID, "Secret")

	cases := []struct {
		name, method, path, token string
		body                      any
		code                      int
		error                     string
	}{
		{"no token", "GET", "/api/v1/sections?projectId=" + project.ID, "", nil, 401, "missing_token"},
		{"no project", "GET", "/api/v1/sections", alice, nil, 400, "project_id_required"},
		{"empty name", "POST", "/api/v1/sections", alice, map[string]any{"project_id": project.ID, "name": "  "}, 400, "invalid_section"},
		{"multi-line name", "POST", "/api/v1/sections", alice, map[string]any{"project_id": project.ID, "name": "a\nb"}, 400, "invalid_section"},
		{"folder", "POST", "/api/v1/sections", alice, map[string]any{"project_id": folder.ID, "name": "x"}, 404, "project_not_found"},
		{"unknown field", "POST", "/api/v1/sections", alice, map[string]any{"project_id": project.ID, "name": "x", "owner": "y"}, 400, "invalid_json"},
		{"bad deleteTasks", "DELETE", "/api/v1/sections/" + section.ID + "?deleteTasks=yes", alice, nil, 400, "invalid_delete_tasks"},
		{"duplicate reorder", "POST", "/api/v1/sections/reorder", alice, map[string]any{"project_id": project.ID, "section_ids": []string{section.ID, section.ID}}, 400, "invalid_section"},
		// Bob sees 404 for everything of Alice's.
		{"foreign list", "GET", "/api/v1/sections?projectId=" + project.ID, bob, nil, 404, "project_not_found"},
		{"foreign create", "POST", "/api/v1/sections", bob, map[string]any{"project_id": project.ID, "name": "x"}, 404, "project_not_found"},
		{"foreign rename", "PATCH", "/api/v1/sections/" + section.ID, bob, map[string]any{"name": "x"}, 404, "section_not_found"},
		{"foreign delete", "DELETE", "/api/v1/sections/" + section.ID, bob, nil, 404, "section_not_found"},
		{"foreign reorder", "POST", "/api/v1/sections/reorder", bob, map[string]any{"project_id": project.ID, "section_ids": []string{section.ID}}, 404, "section_not_found"},
		{"foreign task section", "POST", "/api/v1/tasks", bob, map[string]any{"title": "x", "section_id": section.ID}, 404, "section_not_found"},
	}
	for _, tc := range cases {
		var failure apiError
		if code := api.do(tc.method, tc.path, tc.token, tc.body, &failure); code != tc.code || failure.Error != tc.error {
			t.Errorf("%s: %d %q, want %d %q", tc.name, code, failure.Error, tc.code, tc.error)
		}
	}
	if got := api.sectionNames(alice, project.ID); !sameStrings(got, []string{"Secret"}) {
		t.Fatalf("alice's sections changed: %v", got)
	}
}
