package store

import (
	"context"
	"testing"
	"time"
)

func TestProgressWeekBoundaries(t *testing.T) {
	for _, tc := range []struct{ zone, now, start, end string }{
		{"Asia/Tehran", "2026-10-16T20:29:59Z", "2026-10-10", "2026-10-17"},
		{"Asia/Tehran", "2026-10-16T20:30:00Z", "2026-10-17", "2026-10-24"},
		{"UTC", "2027-01-01T23:59:59Z", "2026-12-26", "2027-01-02"},
		{"America/New_York", "2026-11-03T12:00:00Z", "2026-10-31", "2026-11-07"},
	} {
		t.Run(tc.zone+tc.now, func(t *testing.T) {
			zone, err := time.LoadLocation(tc.zone)
			if err != nil {
				t.Fatal(err)
			}
			now, err := time.Parse(time.RFC3339, tc.now)
			if err != nil {
				t.Fatal(err)
			}
			start, end := ProgressWeek(now, zone)
			if start.Format("2006-01-02") != tc.start || end.Format("2006-01-02") != tc.end || start.Hour() != 0 || end.Hour() != 0 {
				t.Fatalf("week = %v to %v", start, end)
			}
		})
	}
}

func TestProgressLevelsAndBadges(t *testing.T) {
	for _, tc := range []struct{ count, level, remainder, badges int }{
		{0, 1, 0, 0}, {1, 1, 10, 1}, {9, 1, 90, 1}, {10, 2, 0, 2}, {50, 6, 0, 3}, {100, 11, 0, 4},
	} {
		p := progressValues(tc.count, 0, 3, time.Now())
		if p.XP != tc.count*10 || p.Level != tc.level || p.LevelXP != tc.remainder || len(p.Badges) != tc.badges {
			t.Fatalf("count %d: %+v", tc.count, p)
		}
	}
	p := progressValues(3, 3, 3, time.Now())
	if p.Badges[len(p.Badges)-1] != "weekly_goal" {
		t.Fatal("missing weekly badge")
	}
}

func TestProgressCountsLocalDaysAndWeekWindow(t *testing.T) {
	pool := testPool(t)
	ctx := context.Background()
	s := New(pool)
	user, err := s.CreateUser(ctx, "days@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	other, err := s.CreateUser(ctx, "private@example.com", "hash")
	if err != nil {
		t.Fatal(err)
	}
	project, err := s.EnsureInboxProject(ctx, user.ID)
	if err != nil {
		t.Fatal(err)
	}
	otherProject, err := s.EnsureInboxProject(ctx, other.ID)
	if err != nil {
		t.Fatal(err)
	}
	// Before Saturday, twice on Saturday, Sunday, then next week's boundary.
	for _, at := range []string{"2026-10-09T20:29:59Z", "2026-10-09T20:30:00Z", "2026-10-10T09:00:00Z", "2026-10-10T20:30:00Z", "2026-10-16T20:30:00Z"} {
		task, err := s.CreateTask(ctx, user.ID, TaskInput{ProjectID: project.ID, Title: "task", Priority: 4})
		if err != nil {
			t.Fatal(err)
		}
		_, err = pool.Exec(ctx, `UPDATE tasks SET completed_at=$2::timestamptz WHERE id=$1`, task.ID, at)
		if err != nil {
			t.Fatal(err)
		}
	}
	task, err := s.CreateTask(ctx, other.ID, TaskInput{ProjectID: otherProject.ID, Title: "private", Priority: 4})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.CompleteTask(ctx, other.ID, task.ID, true); err != nil {
		t.Fatal(err)
	}
	zone, err := time.LoadLocation("Asia/Tehran")
	if err != nil {
		t.Fatal(err)
	}
	now, _ := time.Parse(time.RFC3339, "2026-10-14T12:00:00Z")
	p, err := s.Progress(ctx, user.ID, now, zone)
	if err != nil {
		t.Fatal(err)
	}
	if p.Completed != 5 || p.WeeklyDays != 2 || p.WeekStart != "2026-10-10" {
		t.Fatalf("window: %+v", p)
	}
}
