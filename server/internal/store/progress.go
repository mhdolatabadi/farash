package store

import (
	"context"
	"time"
	_ "time/tzdata"
)

// Progress is derived from live completed tasks, so retries cannot award XP
// twice and undo/deletion automatically remove the corresponding credit.
type Progress struct {
	Completed  int      `json:"completed"`
	XP         int      `json:"xp"`
	Level      int      `json:"level"`
	LevelXP    int      `json:"level_xp"`
	WeeklyDays int      `json:"weekly_days"`
	WeeklyGoal int      `json:"weekly_goal"`
	WeekStart  string   `json:"week_start"`
	Badges     []string `json:"badges"`
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
	start, end := ProgressWeek(now, zone)
	var completed, days, goal int
	err := s.pool.QueryRow(ctx, `SELECT u.weekly_active_days,
 (SELECT count(*) FROM tasks WHERE owner_id=u.id AND deleted_at IS NULL AND completed_at IS NOT NULL),
 (SELECT count(DISTINCT (completed_at AT TIME ZONE $4)::date) FROM tasks
 WHERE owner_id=u.id AND deleted_at IS NULL AND completed_at >= $2 AND completed_at < $3)
 FROM users u WHERE u.id=$1`, owner, start, end, zone.String()).Scan(&goal, &completed, &days)
	if err != nil {
		return Progress{}, err
	}
	return progressValues(completed, days, goal, start), nil
}

func (s *Store) SetProgressGoal(ctx context.Context, owner string, days int) error {
	if days < 1 || days > 7 {
		return ErrInvalidTask
	}
	_, err := s.pool.Exec(ctx, `UPDATE users SET weekly_active_days=$2 WHERE id=$1`, owner, days)
	return err
}
