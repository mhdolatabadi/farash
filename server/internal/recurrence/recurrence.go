// Package recurrence calculates bounded, deterministic future occurrences.
// It deliberately has no database, task mutation, or system-clock dependency.
package recurrence

import (
	"errors"
	"fmt"
	"time"
	_ "time/tzdata"
)

type Frequency string
type Calendar string
type Basis string

const (
	Daily          Frequency = "day"
	Weekly         Frequency = "week"
	Monthly        Frequency = "month"
	Yearly         Frequency = "year"
	Gregorian      Calendar  = "gregorian"
	Jalali         Calendar  = "jalali"
	FromDue        Basis     = "due"
	FromCompletion Basis     = "completion"
)

var (
	ErrInvalidRule     = errors.New("invalid recurrence rule")
	ErrInvalidSchedule = errors.New("invalid recurrence schedule")
	ErrInvalidCursor   = errors.New("invalid recurrence cursor")
)

const dateLayout = "2006-01-02"

// Rule is the serializable scheduling contract, not a stored task yet.
type Rule struct {
	Frequency   Frequency      `json:"frequency"`
	Interval    int            `json:"interval"`
	Calendar    Calendar       `json:"calendar"`
	Basis       Basis          `json:"basis"`
	Weekdays    []time.Weekday `json:"weekdays,omitempty"`
	MonthDay    int            `json:"month_day,omitempty"`
	LastWeekday *time.Weekday  `json:"last_weekday,omitempty"`
	Until       string         `json:"until,omitempty"`
	Count       int            `json:"count,omitempty"`
}

type Schedule struct {
	Start    string `json:"start"`
	Time     string `json:"time,omitempty"`
	Timezone string `json:"timezone"`
	Rule     Rule   `json:"rule"`
}

type Occurrence struct {
	Date     string     `json:"date"`
	Datetime *time.Time `json:"datetime,omitempty"`
	Timezone string     `json:"timezone"`
}

func parseDate(value string) (time.Time, bool) {
	day, err := time.Parse(dateLayout, value)
	return day, err == nil && day.Year() >= 1900 && day.Year() < 2200 && day.Format(dateLayout) == value
}

func (r Rule) Validate() error {
	invalid := func(field string) error { return fmt.Errorf("%w: %s", ErrInvalidRule, field) }
	if r.Frequency != Daily && r.Frequency != Weekly && r.Frequency != Monthly && r.Frequency != Yearly {
		return invalid("frequency")
	}
	if r.Interval < 1 || r.Interval > 1000 {
		return invalid("interval")
	}
	if r.Calendar != Gregorian && r.Calendar != Jalali {
		return invalid("calendar")
	}
	if r.Basis != FromDue && r.Basis != FromCompletion {
		return invalid("basis")
	}
	if r.Count < 0 || r.Count > 1000000 {
		return invalid("count")
	}
	if r.Until != "" {
		if _, valid := parseDate(r.Until); !valid {
			return invalid("until")
		}
	}
	seen := [7]bool{}
	for _, weekday := range r.Weekdays {
		if r.Frequency != Weekly || weekday < time.Sunday || weekday > time.Saturday || seen[weekday] {
			return invalid("weekdays")
		}
		seen[weekday] = true
	}
	if r.MonthDay < 0 || r.MonthDay > 31 || r.MonthDay != 0 && r.Frequency != Monthly {
		return invalid("month_day")
	}
	if r.LastWeekday != nil && (r.Frequency != Monthly || r.MonthDay != 0 || *r.LastWeekday < time.Sunday || *r.LastWeekday > time.Saturday) {
		return invalid("last_weekday")
	}
	return nil
}

func saturday(day time.Time) time.Time {
	return day.AddDate(0, 0, -((int(day.Weekday()) + 1) % 7))
}

func eligible(day, anchor time.Time, r Rule) bool {
	days := daysBetween(anchor, day)
	if days < 0 {
		return false
	}
	switch r.Frequency {
	case Daily:
		return days%r.Interval == 0
	case Weekly:
		weeks := daysBetween(saturday(anchor), saturday(day)) / 7
		if weeks%r.Interval != 0 || r.Basis == FromCompletion && weeks < r.Interval {
			return false
		}
		if len(r.Weekdays) == 0 {
			return day.Weekday() == anchor.Weekday()
		}
		for _, weekday := range r.Weekdays {
			if day.Weekday() == weekday {
				return true
			}
		}
		return false
	case Monthly, Yearly:
		ay, am, ad := calendarDate(anchor, r.Calendar)
		y, m, d := calendarDate(day, r.Calendar)
		period := (y-ay)*12 + m - am
		if r.Frequency == Yearly {
			if m != am {
				return false
			}
			period = y - ay
		}
		if period < 0 || period%r.Interval != 0 || r.Basis == FromCompletion && period < r.Interval {
			return false
		}
		length := monthLength(y, m, r.Calendar)
		if r.LastWeekday != nil {
			return day.Weekday() == *r.LastWeekday && d+7 > length
		}
		if r.MonthDay != 0 {
			ad = r.MonthDay
		}
		return d == min(ad, length)
	}
	return false
}

// wallMoment returns the earliest instant matching a wall time. Offsets
// around the local date capture both sides of DST, including half-hour
// changes and international date-line moves. Missing wall times are skipped.
func wallMoment(day time.Time, hour, minute int, zone *time.Location) (time.Time, bool) {
	nominal := time.Date(day.Year(), day.Month(), day.Day(), hour, minute, 0, 0, time.UTC)
	offsets := map[int]bool{}
	for hours := -48; hours <= 48; hours += 12 {
		_, offset := nominal.Add(time.Duration(hours) * time.Hour).In(zone).Zone()
		offsets[offset] = true
	}
	var earliest time.Time
	for offset := range offsets {
		candidate := nominal.Add(-time.Duration(offset) * time.Second)
		local := candidate.In(zone)
		if civilDate(local) != day || local.Hour() != hour || local.Minute() != minute || local.Second() != 0 {
			continue
		}
		if earliest.IsZero() || candidate.Before(earliest) {
			earliest = candidate
		}
	}
	return earliest, !earliest.IsZero()
}

// Next returns the next occurrence after a completion or skip. emitted is
// the number already issued, including the original start. Exhaustion is
// (zero, false, nil); invalid input returns a wrapped sentinel error.
func Next(schedule Schedule, after time.Time, emitted int) (Occurrence, bool, error) {
	if err := schedule.Rule.Validate(); err != nil {
		return Occurrence{}, false, err
	}
	invalid := func(field string) (Occurrence, bool, error) {
		return Occurrence{}, false, fmt.Errorf("%w: %s", ErrInvalidSchedule, field)
	}
	start, valid := parseDate(schedule.Start)
	if !valid {
		return invalid("start")
	}
	if schedule.Timezone == "" || schedule.Timezone == "Local" {
		return invalid("timezone")
	}
	zone, err := time.LoadLocation(schedule.Timezone)
	if err != nil {
		return invalid("timezone")
	}
	hour, minute := 0, 0
	if schedule.Time != "" {
		wall, err := time.Parse("15:04", schedule.Time)
		if err != nil || wall.Format("15:04") != schedule.Time {
			return invalid("time")
		}
		hour, minute = wall.Hour(), wall.Minute()
		if _, exists := wallMoment(start, hour, minute, zone); !exists {
			return invalid("start wall time does not exist")
		}
	}
	if after.IsZero() || after.In(zone).Year() < 1900 || after.In(zone).Year() >= 2200 || emitted < 1 {
		return Occurrence{}, false, ErrInvalidCursor
	}
	rule := schedule.Rule
	// The original occurrence must satisfy its selectors, independently of
	// completion-based re-anchoring of subsequent occurrences.
	initial := rule
	initial.Basis = FromDue
	if !eligible(start, start, initial) {
		return invalid("start does not match selectors")
	}
	var until time.Time
	if rule.Until != "" {
		until, _ = parseDate(rule.Until)
		if until.Before(start) {
			return invalid("until precedes start")
		}
	}
	if rule.Count > 0 && emitted >= rule.Count {
		return Occurrence{}, false, nil
	}
	anchor := start
	if rule.Basis == FromCompletion {
		anchor = civilDate(after.In(zone))
	}
	day := civilDate(after.In(zone))
	if day.Before(anchor) {
		day = anchor
	}
	for ; day.Year() < 2200; day = day.AddDate(0, 0, 1) {
		if !until.IsZero() && day.After(until) {
			break
		}
		if day == anchor || !eligible(day, anchor, rule) {
			continue
		}
		result := Occurrence{Date: day.Format(dateLayout), Timezone: schedule.Timezone}
		if schedule.Time == "" {
			// Whole-day repeats advance beyond the completion's local date.
			if !day.After(civilDate(after.In(zone))) {
				continue
			}
			return result, true, nil
		}
		moment, exists := wallMoment(day, hour, minute, zone)
		if !exists || !moment.After(after) {
			continue
		}
		result.Datetime = &moment
		return result, true, nil
	}
	return Occurrence{}, false, nil
}
