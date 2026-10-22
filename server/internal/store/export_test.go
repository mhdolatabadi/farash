package store

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func TestExportBudgetNeverTruncatesSuccess(t *testing.T) {
	for _, test := range []struct {
		name   string
		budget exportBudget
		record []byte
	}{
		{"rows", exportBudget{records: exportMaxRecords}, []byte("{}")},
		{"bytes", exportBudget{bytes: exportMaxBytes - 2}, []byte("{}")},
	} {
		t.Run(test.name, func(t *testing.T) {
			if err := test.budget.add(test.record); !errors.Is(err, ErrExportTooLarge) {
				t.Fatalf("limit must fail: %v", err)
			}
		})
	}
	budget := exportBudget{records: exportMaxRecords - 1, bytes: exportMaxBytes - 3}
	if err := budget.add([]byte("{}")); err != nil {
		t.Fatalf("exact limits: %v", err)
	}
}

func TestExportPreservesOwnedRecordsAndHistory(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	s := New(pool)
	for _, statement := range []string{
		`INSERT INTO users(id,email,password_hash) VALUES ('a','a@example.com','private-password-hash'),('b','b@example.com','other-password-hash')`,
		`INSERT INTO projects(id,owner_id,name,method) VALUES ('pa','a','مطالعه','scrum'),('pb','b','SECRET OTHER PROJECT','simple')`,
		`INSERT INTO sections(id,owner_id,project_id,name) VALUES ('section','a','pa','بخش اول')`,
		`INSERT INTO tasks(id,owner_id,project_id,section_id,title,description,completed_at) VALUES ('parent','a','pa','section','کتاب','متن فارسی',now())`,
		`INSERT INTO tasks(id,owner_id,project_id,section_id,parent_id,title,deleted_at) VALUES ('child','a','pa','section','parent','فصل',now())`,
		`INSERT INTO tasks(id,owner_id,project_id,title) VALUES ('other','b','pb','SECRET OTHER TASK')`,
		`INSERT INTO labels(id,owner_id,name) VALUES ('label','a','خانه')`,
		`INSERT INTO task_labels(owner_id,task_id,label_id) VALUES ('a','parent','label')`,
		`INSERT INTO time_entries(id,owner_id,task_id,task_title,started_at,ended_at,source,request_key) VALUES ('time','a','parent','کتاب',now()-interval '2 minutes',now()-interval '1 minute','manual','time-key')`,
		`INSERT INTO sprints(id,owner_id,project_id,request_key,name,starts_on,ends_on,state,closed_at,closed_tracked_seconds,review) VALUES ('sprint','a','pa','sprint-key','نوبت',current_date,current_date,'closed',now(),60,'مرور')`,
		`INSERT INTO scrum_items(task_id,owner_id,sprint_id,points,acceptance) VALUES ('parent','a','sprint',3,'معیار')`,
		`INSERT INTO sprint_scope(sprint_id,task_id,title,points,completed) VALUES ('sprint','removed-task','عنوان تاریخی',5,true)`,
		`INSERT INTO sprint_events(sprint_id,kind,scope_points,remaining_points,scope_count,remaining_count) VALUES ('sprint','closed',5,0,1,0)`,
	} {
		if _, err := pool.Exec(ctx, statement); err != nil {
			t.Fatal(err)
		}
	}
	body, err := s.ExportAccount(ctx, "a")
	if err != nil {
		t.Fatal(err)
	}
	var document accountExport
	if err := json.Unmarshal(body, &document); err != nil {
		t.Fatal(err)
	}
	if document.Format != "farash-export" || document.Version != 1 || document.ExportedAt.IsZero() {
		t.Fatalf("invalid envelope: %+v", document)
	}
	want := map[string]int{"projects": 1, "sections": 1, "tasks": 2, "labels": 1, "task_labels": 1, "time_entries": 1, "sprints": 1, "scrum_items": 1, "sprint_scope": 1, "sprint_events": 1}
	for table, count := range want {
		if len(document.Records[table]) != count {
			t.Fatalf("%s count: %d", table, len(document.Records[table]))
		}
	}
	for _, forbidden := range []string{"password_hash", "private-password-hash", "SECRET OTHER", "owner_id", "a@example.com"} {
		if strings.Contains(string(body), forbidden) {
			t.Fatalf("private/internal value exported: %s", forbidden)
		}
	}
	for _, retained := range []string{"متن فارسی", "completed_at", "deleted_at", "parent_id", "removed-task", "عنوان تاریخی", "closed_tracked_seconds", "due_timezone", "weekly_task_goal"} {
		if !strings.Contains(string(body), retained) {
			t.Fatalf("portable data omitted: %s", retained)
		}
	}
	if _, err := s.ExportAccount(ctx, "missing"); !errors.Is(err, ErrUserNotFound) {
		t.Fatalf("unknown account: %v", err)
	}
	other, err := s.ExportAccount(ctx, "b")
	if err != nil || strings.Contains(string(other), "متن فارسی") || strings.Contains(string(other), "عنوان تاریخی") {
		t.Fatalf("other account isolation: %v", err)
	}
}

func TestExportEmptyAccountHasStableArrays(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	s := New(pool)
	if _, err := pool.Exec(ctx, `INSERT INTO users(id,email,password_hash) VALUES ('empty','empty@example.com','hash')`); err != nil {
		t.Fatal(err)
	}
	body, err := s.ExportAccount(ctx, "empty")
	if err != nil {
		t.Fatal(err)
	}
	var document accountExport
	if err := json.Unmarshal(body, &document); err != nil {
		t.Fatal(err)
	}
	if len(document.Records) != len(exportQueries) {
		t.Fatal("missing empty collections")
	}
	for name, records := range document.Records {
		if records == nil || len(records) != 0 {
			t.Fatalf("unstable empty array %s: %s", name, body)
		}
	}
}
