package recurrence

import (
	"encoding/json"
	"errors"
	"reflect"
	"testing"
	"time"
)

func instant(t *testing.T, value string) time.Time {
	t.Helper()
	moment, err := time.Parse(time.RFC3339, value)
	if err != nil {
		t.Fatal(err)
	}
	return moment
}

func baseRule(frequency Frequency) Rule {
	return Rule{Frequency: frequency, Interval: 1, Calendar: Gregorian, Basis: FromDue}
}

func weekday(day time.Weekday) *time.Weekday { return &day }

func TestNext(t *testing.T) {
	tests := []struct {
		name, start, after, want string
		rule                     Rule
	}{
		{"daily", "2026-10-01", "2026-10-01", "2026-10-02", baseRule(Daily)},
		{"daily interval late", "2026-10-01", "2026-10-12", "2026-10-13", Rule{Frequency: Daily, Interval: 3, Calendar: Gregorian, Basis: FromDue}},
		{"completion daily", "2026-10-01", "2026-10-12", "2026-10-15", Rule{Frequency: Daily, Interval: 3, Calendar: Gregorian, Basis: FromCompletion}},
		{"early due completion", "2026-10-10", "2026-10-01", "2026-10-11", baseRule(Daily)},
		{"early completion basis", "2026-10-10", "2026-10-01", "2026-10-02", Rule{Frequency: Daily, Interval: 1, Calendar: Gregorian, Basis: FromCompletion}},
		{"weekly inherited", "2026-10-03", "2026-10-03", "2026-10-10", baseRule(Weekly)},
		{"weekly selected same bucket", "2026-10-03", "2026-10-03", "2026-10-06", Rule{Frequency: Weekly, Interval: 2, Calendar: Gregorian, Basis: FromDue, Weekdays: []time.Weekday{time.Tuesday, time.Saturday}}},
		{"weekly skip ineligible bucket", "2026-10-03", "2026-10-06", "2026-10-17", Rule{Frequency: Weekly, Interval: 2, Calendar: Gregorian, Basis: FromDue, Weekdays: []time.Weekday{time.Tuesday, time.Saturday}}},
		{"completion weekly selected", "2026-10-03", "2026-10-06", "2026-10-17", Rule{Frequency: Weekly, Interval: 2, Calendar: Gregorian, Basis: FromCompletion, Weekdays: []time.Weekday{time.Saturday, time.Tuesday}}},
		{"monthly short", "2025-01-31", "2025-01-31", "2025-02-28", baseRule(Monthly)},
		{"monthly no drift", "2025-01-31", "2025-02-28", "2025-03-31", baseRule(Monthly)},
		{"monthly overdue", "2025-01-31", "2025-03-02", "2025-03-31", baseRule(Monthly)},
		{"monthly interval", "2025-01-31", "2025-01-31", "2025-03-31", Rule{Frequency: Monthly, Interval: 2, Calendar: Gregorian, Basis: FromDue}},
		{"completion monthly", "2025-01-31", "2025-02-28", "2025-03-28", Rule{Frequency: Monthly, Interval: 1, Calendar: Gregorian, Basis: FromCompletion}},
		{"fixed monthly day", "2025-02-28", "2025-02-28", "2025-03-31", Rule{Frequency: Monthly, Interval: 1, Calendar: Gregorian, Basis: FromDue, MonthDay: 31}},
		{"monthly last Friday", "2026-01-30", "2026-01-30", "2026-02-27", Rule{Frequency: Monthly, Interval: 1, Calendar: Gregorian, Basis: FromDue, LastWeekday: weekday(time.Friday)}},
		{"completion last Friday", "2026-01-30", "2026-02-05", "2026-03-27", Rule{Frequency: Monthly, Interval: 1, Calendar: Gregorian, Basis: FromCompletion, LastWeekday: weekday(time.Friday)}},
		{"yearly leap clamp", "2024-02-29", "2024-02-29", "2025-02-28", baseRule(Yearly)},
		{"yearly leap returns", "2024-02-29", "2027-02-28", "2028-02-29", baseRule(Yearly)},
		{"yearly interval", "2024-02-29", "2024-02-29", "2028-02-29", Rule{Frequency: Yearly, Interval: 4, Calendar: Gregorian, Basis: FromDue}},
		{"Jalali month clamp", "2025-09-22", "2025-09-22", "2025-10-22", Rule{Frequency: Monthly, Interval: 1, Calendar: Jalali, Basis: FromDue}},
		{"Jalali explicit 31 returns", "2025-10-22", "2026-03-21", "2026-04-20", Rule{Frequency: Monthly, Interval: 1, Calendar: Jalali, Basis: FromDue, MonthDay: 31}},
		{"Jalali last Friday", "2026-10-16", "2026-10-16", "2026-11-20", Rule{Frequency: Monthly, Interval: 1, Calendar: Jalali, Basis: FromDue, LastWeekday: weekday(time.Friday)}},
		{"Jalali leap Esfand", "2025-03-20", "2025-03-20", "2026-03-20", Rule{Frequency: Yearly, Interval: 1, Calendar: Jalali, Basis: FromDue}},
		{"Jalali completion year", "2025-03-20", "2025-03-21", "2026-03-21", Rule{Frequency: Yearly, Interval: 1, Calendar: Jalali, Basis: FromCompletion}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			schedule := Schedule{Start: tt.start, Timezone: "UTC", Rule: tt.rule}
			before, _ := json.Marshal(schedule)
			got, ok, err := Next(schedule, instant(t, tt.after+"T12:00:00Z"), 1)
			if err != nil || !ok || got.Date != tt.want || got.Datetime != nil || got.Timezone != "UTC" {
				t.Fatalf("Next = %#v, %v, %v; want %s", got, ok, err, tt.want)
			}
			after, _ := json.Marshal(schedule)
			if string(before) != string(after) {
				t.Fatal("schedule mutated")
			}
		})
	}
}

func TestTimezoneAndDST(t *testing.T) {
	tests := []struct {
		name, start, wall, zone, after, date, utc string
	}{
		{"Tehran wall time", "2026-10-01", "09:15", "Asia/Tehran", "2026-10-01T12:00:00Z", "2026-10-02", "2026-10-02T05:45:00Z"},
		{"local date before UTC midnight", "2026-10-01", "23:00", "America/Los_Angeles", "2026-10-02T05:00:00Z", "2026-10-02", "2026-10-03T06:00:00Z"},
		{"spring gap skipped", "2026-03-07", "02:30", "America/New_York", "2026-03-07T12:00:00Z", "2026-03-09", "2026-03-09T06:30:00Z"},
		{"fall fold earliest", "2026-10-31", "01:30", "America/New_York", "2026-10-31T12:00:00Z", "2026-11-01", "2026-11-01T05:30:00Z"},
		{"fold second instant not reissued", "2026-10-31", "01:30", "America/New_York", "2026-11-01T06:00:00Z", "2026-11-02", "2026-11-02T06:30:00Z"},
		{"half-hour fold", "2026-04-04", "01:45", "Australia/Lord_Howe", "2026-04-04T01:00:00Z", "2026-04-05", "2026-04-04T14:45:00Z"},
		{"half-hour gap", "2026-10-03", "02:15", "Australia/Lord_Howe", "2026-10-03T01:00:00Z", "2026-10-05", "2026-10-04T15:15:00Z"},
		{"date-line missing day", "2011-12-29", "09:00", "Pacific/Apia", "2011-12-29T20:00:00Z", "2011-12-31", "2011-12-30T19:00:00Z"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			schedule := Schedule{Start: tt.start, Time: tt.wall, Timezone: tt.zone, Rule: baseRule(Daily)}
			got, ok, err := Next(schedule, instant(t, tt.after), 1)
			if err != nil || !ok || got.Date != tt.date || got.Datetime == nil || got.Datetime.Format(time.RFC3339) != tt.utc {
				t.Fatalf("Next = %#v, %v, %v; want %s %s", got, ok, err, tt.date, tt.utc)
			}
		})
	}
	// Whole-day boundaries use the explicit zone, without a fake timestamp.
	s := Schedule{Start: "2026-10-01", Timezone: "Asia/Tehran", Rule: baseRule(Daily)}
	got, ok, err := Next(s, instant(t, "2026-10-01T21:00:00Z"), 1)
	if err != nil || !ok || got.Date != "2026-10-03" || got.Datetime != nil {
		t.Fatalf("whole-day local boundary: %#v %v %v", got, ok, err)
	}
}

func TestLimits(t *testing.T) {
	s := Schedule{Start: "2026-10-01", Timezone: "UTC", Rule: baseRule(Daily)}
	s.Rule.Count = 2
	s.Rule.Until = "2026-10-02"
	got, ok, err := Next(s, instant(t, "2026-10-01T12:00:00Z"), 1)
	if err != nil || !ok || got.Date != "2026-10-02" {
		t.Fatalf("inclusive until: %#v %v %v", got, ok, err)
	}
	for _, emitted := range []int{2, 3} {
		if _, ok, err := Next(s, instant(t, "2026-10-01T12:00:00Z"), emitted); err != nil || ok {
			t.Fatalf("count exhausted: %v %v", ok, err)
		}
	}
	if _, ok, err := Next(s, instant(t, "2026-10-02T12:00:00Z"), 1); err != nil || ok {
		t.Fatalf("until exhausted: %v %v", ok, err)
	}
	s.Rule.Until = ""
	s.Rule.Count = 1
	if _, ok, err := Next(s, instant(t, "2026-10-01T12:00:00Z"), 1); err != nil || ok {
		t.Fatalf("single occurrence: %v %v", ok, err)
	}
	s.Start = "2199-12-31"
	s.Rule.Count = 0
	if _, ok, err := Next(s, instant(t, "2199-12-31T12:00:00Z"), 1); err != nil || ok {
		t.Fatalf("range exhausted: %v %v", ok, err)
	}
	// Skipped DST slots do not consume the emitted occurrence limit.
	s = Schedule{Start: "2026-03-07", Time: "02:30", Timezone: "America/New_York", Rule: baseRule(Daily)}
	s.Rule.Count = 2
	got, ok, err = Next(s, instant(t, "2026-03-07T12:00:00Z"), 1)
	if err != nil || !ok || got.Date != "2026-03-09" {
		t.Fatalf("gap consumed count: %#v %v %v", got, ok, err)
	}
}

func TestInvalidRulesAndSchedules(t *testing.T) {
	rules := []Rule{
		{},
		{Frequency: "hour", Interval: 1, Calendar: Gregorian, Basis: FromDue},
		{Frequency: Daily, Interval: 0, Calendar: Gregorian, Basis: FromDue},
		{Frequency: Daily, Interval: 1001, Calendar: Gregorian, Basis: FromDue},
		{Frequency: Daily, Interval: 1, Calendar: "lunar", Basis: FromDue},
		{Frequency: Daily, Interval: 1, Calendar: Gregorian, Basis: "now"},
		{Frequency: Weekly, Interval: 1, Calendar: Gregorian, Basis: FromDue, Weekdays: []time.Weekday{time.Monday, time.Monday}},
		{Frequency: Weekly, Interval: 1, Calendar: Gregorian, Basis: FromDue, Weekdays: []time.Weekday{-1}},
		{Frequency: Weekly, Interval: 1, Calendar: Gregorian, Basis: FromDue, Weekdays: []time.Weekday{7}},
		{Frequency: Daily, Interval: 1, Calendar: Gregorian, Basis: FromDue, Weekdays: []time.Weekday{time.Monday}},
		{Frequency: Daily, Interval: 1, Calendar: Gregorian, Basis: FromDue, MonthDay: 1},
		{Frequency: Monthly, Interval: 1, Calendar: Gregorian, Basis: FromDue, MonthDay: 32},
		{Frequency: Monthly, Interval: 1, Calendar: Gregorian, Basis: FromDue, MonthDay: -1},
		{Frequency: Monthly, Interval: 1, Calendar: Gregorian, Basis: FromDue, MonthDay: 1, LastWeekday: weekday(time.Monday)},
		{Frequency: Monthly, Interval: 1, Calendar: Gregorian, Basis: FromDue, LastWeekday: weekday(7)},
		{Frequency: Yearly, Interval: 1, Calendar: Gregorian, Basis: FromDue, LastWeekday: weekday(time.Friday)},
		{Frequency: Daily, Interval: 1, Calendar: Gregorian, Basis: FromDue, Until: "2026-02-30"},
		{Frequency: Daily, Interval: 1, Calendar: Gregorian, Basis: FromDue, Count: -1},
		{Frequency: Daily, Interval: 1, Calendar: Gregorian, Basis: FromDue, Count: 1000001},
	}
	for _, rule := range rules {
		_, _, err := Next(Schedule{Start: "2026-10-01", Timezone: "UTC", Rule: rule}, instant(t, "2026-10-01T12:00:00Z"), 1)
		if !errors.Is(err, ErrInvalidRule) {
			t.Errorf("rule %#v: %v", rule, err)
		}
	}
	base := Schedule{Start: "2026-10-01", Timezone: "UTC", Rule: baseRule(Daily)}
	for _, mutate := range []func(*Schedule){
		func(s *Schedule) { s.Start = "2026-02-30" },
		func(s *Schedule) { s.Start = "1899-12-31" },
		func(s *Schedule) { s.Start = "2200-01-01" },
		func(s *Schedule) { s.Start = "2026-1-1" },
		func(s *Schedule) { s.Time = "24:00" },
		func(s *Schedule) { s.Time = "9:00" },
		func(s *Schedule) { s.Timezone = "Local" },
		func(s *Schedule) { s.Timezone = "" },
		func(s *Schedule) { s.Timezone = "not/a-zone" },
		func(s *Schedule) { s.Start = "2026-03-08"; s.Time = "02:30"; s.Timezone = "America/New_York" },
		func(s *Schedule) { s.Rule.Until = "2026-09-30" },
		func(s *Schedule) { s.Rule = baseRule(Weekly); s.Rule.Weekdays = []time.Weekday{time.Monday} },
		func(s *Schedule) { s.Rule = baseRule(Monthly); s.Rule.MonthDay = 15 },
		func(s *Schedule) { s.Rule = baseRule(Monthly); s.Rule.LastWeekday = weekday(time.Friday) },
	} {
		s := base
		mutate(&s)
		_, _, err := Next(s, instant(t, "2026-10-01T12:00:00Z"), 1)
		if !errors.Is(err, ErrInvalidSchedule) {
			t.Errorf("schedule %#v: %v", s, err)
		}
	}
	for _, cursor := range []struct {
		after   time.Time
		emitted int
	}{
		{time.Time{}, 1}, {instant(t, "1899-01-01T00:00:00Z"), 1},
		{instant(t, "2200-01-01T00:00:00Z"), 1}, {instant(t, "2026-10-01T00:00:00Z"), 0},
	} {
		if _, _, err := Next(base, cursor.after, cursor.emitted); !errors.Is(err, ErrInvalidCursor) {
			t.Errorf("cursor %#v: %v", cursor, err)
		}
	}
}

func TestSuccessiveOccurrencesRetainAnchor(t *testing.T) {
	s := Schedule{Start: "2024-01-31", Time: "09:00", Timezone: "Asia/Tehran", Rule: baseRule(Monthly)}
	after := instant(t, "2024-01-31T08:00:00Z")
	for i, want := range []string{"2024-02-29", "2024-03-31", "2024-04-30", "2024-05-31"} {
		got, ok, err := Next(s, after, i+1)
		if err != nil || !ok || got.Date != want || got.Datetime == nil {
			t.Fatalf("successive occurrence: %#v %v %v; want %s", got, ok, err, want)
		}
		after = got.Datetime.Add(time.Hour)
	}
	// Until is inclusive in the chosen zone, rather than the UTC date.
	s = Schedule{Start: "2026-10-01", Time: "23:00", Timezone: "America/Los_Angeles", Rule: baseRule(Daily)}
	s.Rule.Until = "2026-10-02"
	got, ok, err := Next(s, instant(t, "2026-10-02T12:00:00Z"), 1)
	if err != nil || !ok || got.Date != "2026-10-02" || got.Datetime.Format(time.RFC3339) != "2026-10-03T06:00:00Z" {
		t.Fatalf("local until: %#v %v %v", got, ok, err)
	}
}

func TestLongRangeAndRuleRoundTrip(t *testing.T) {
	s := Schedule{Start: "1900-01-01", Timezone: "UTC", Rule: Rule{Frequency: Daily, Interval: 3, Calendar: Gregorian, Basis: FromDue}}
	got, ok, err := Next(s, instant(t, "2199-12-01T00:00:00Z"), 1)
	if err != nil || !ok {
		t.Fatalf("long range: %#v %v %v", got, ok, err)
	}
	day, _ := parseDate(got.Date)
	start, _ := parseDate(s.Start)
	if daysBetween(start, day)%3 != 0 || daysBetween(instant(t, "2199-12-01T00:00:00Z"), day) > 3 {
		t.Fatalf("duration overflow/drift: %s", got.Date)
	}
	s.Rule = Rule{Frequency: Monthly, Interval: 2, Calendar: Jalali, Basis: FromCompletion, LastWeekday: weekday(time.Friday), Until: "2027-01-01", Count: 12}
	encoded, err := json.Marshal(s)
	if err != nil {
		t.Fatal(err)
	}
	var decoded Schedule
	if err := json.Unmarshal(encoded, &decoded); err != nil || !reflect.DeepEqual(s, decoded) {
		t.Fatalf("rule round trip: %s %v", encoded, err)
	}
}
