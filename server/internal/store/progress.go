package store

import (
	"context"
	"encoding/json"
	"time"
	_ "time/tzdata"
)

// Progress is derived from live completed tasks, so retries cannot award XP
// twice and undo/deletion automatically remove the corresponding credit.
type Progress struct {
	Completed  int         `json:"completed"`
	XP         int         `json:"xp"`
	Level      int         `json:"level"`
	LevelXP    int         `json:"level_xp"`
	WeeklyDays int         `json:"weekly_days"`
	WeeklyGoal int         `json:"weekly_goal"`
	WeekStart  string      `json:"week_start"`
	Badges     []string    `json:"badges"`
	WeekReport *WeekReport `json:"week_report,omitempty"`
}

type ProgressDay struct {
	Date      string `json:"date"`
	Completed int    `json:"completed"`
	Future    bool   `json:"future"`
}

type WeekReport struct {
	Completed         int           `json:"completed"`
	PreviousCompleted int           `json:"previous_completed"`
	ComparedThrough   string        `json:"compared_through"`
	Days              []ProgressDay `json:"days"`
}

func weekReport(start, now time.Time, counts map[string]int, previous int) *WeekReport {
	report := &WeekReport{PreviousCompleted: previous, ComparedThrough: now.Format(time.RFC3339), Days: []ProgressDay{}}
	today := now.Format("2006-01-02")
	for day := 0; day < 7; day++ {
		date := start.AddDate(0, 0, day).Format("2006-01-02")
		count := counts[date]
		report.Completed += count
		report.Days = append(report.Days, ProgressDay{Date: date, Completed: count, Future: date > today})
	}
	return report
}

// Weeks start Saturday at midnight in the requested IANA time zone.
func ProgressWeek(now time.Time, zone *time.Location) (time.Time, time.Time) {
	local := now.In(zone)
	start := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, zone)
	start = start.AddDate(0, 0, -(int(local.Weekday())+1)%7)
	return start, start.AddDate(0, 0, 7)
}

func progressValues(completed, days, goal int, start time.Time) Progress {
	xp := completed * 10
	p := Progress{Completed: completed, XP: xp, Level: xp/100 + 1, LevelXP: xp % 100,
		WeeklyDays: days, WeeklyGoal: goal, WeekStart: start.Format("2006-01-02"), Badges: []string{}}
	for _, b := range []struct {
		count int
		name  string
	}{{1, "first_step"}, {10, "ten_tasks"}, {50, "fifty_tasks"}, {100, "hundred_tasks"}} {
		if completed >= b.count {
			p.Badges = append(p.Badges, b.name)
		}
	}
	if days >= goal {
		p.Badges = append(p.Badges, "weekly_goal")
	}
	return p
}

func (s *Store) Progress(ctx context.Context, owner string, now time.Time, zone *time.Location) (Progress, error) {
	now = now.In(zone)
	start, _ := ProgressWeek(now, zone)
	previousStart := start.AddDate(0, 0, -7)
	previousEnd := now.AddDate(0, 0, -7)
	var completed, goal, previous int
	var dailyJSON []byte
	err := s.pool.QueryRow(ctx, `SELECT u.weekly_active_days,
 (SELECT count(*) FROM tasks WHERE owner_id=u.id AND deleted_at IS NULL AND completed_at IS NOT NULL),
 (SELECT COALESCE(jsonb_object_agg(day,total),'{}'::jsonb) FROM (
  SELECT to_char(completed_at AT TIME ZONE $4,'YYYY-MM-DD') AS day,count(*) AS total
  FROM tasks WHERE owner_id=u.id AND deleted_at IS NULL AND completed_at >= $2 AND completed_at <= $3 GROUP BY 1
 ) days),
 (SELECT count(*) FROM tasks WHERE owner_id=u.id AND deleted_at IS NULL AND completed_at >= $5 AND completed_at <= $6)
 FROM users u WHERE u.id=$1`, owner, start, now, zone.String(), previousStart, previousEnd).Scan(&goal, &completed, &dailyJSON, &previous)
	if err != nil {
		return Progress{}, err
	}
	counts := map[string]int{}
	if err := json.Unmarshal(dailyJSON, &counts); err != nil {
		return Progress{}, err
	}
	p := progressValues(completed, len(counts), goal, start)
	p.WeekReport = weekReport(start, now, counts, previous)
	return p, nil
}

func (s *Store) SetProgressGoal(ctx context.Context, owner string, days int) error {
	if days < 1 || days > 7 {
		return ErrInvalidTask
	}
	_, err := s.pool.Exec(ctx, `UPDATE users SET weekly_active_days=$2 WHERE id=$1`, owner, days)
	return err
}
