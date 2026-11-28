package store

import (
	"strings"
	"testing"
	"time"
)

func TestCalendarEventValidation(t *testing.T) {
	ptr := func(s string) *string { return &s }
	valid := func() CalendarEventInput {
		return CalendarEventInput{Title: ptr("  جلسه  "), StartAt: ptr("2026-11-27T23:30:00+03:30"), EndAt: ptr("2026-11-28T01:00:00+03:30"), TimeZone: ptr("Asia/Tehran")}
	}
	var event CalendarEvent
	if err := valid().apply(&event); err != nil || event.Title != "جلسه" || event.EndAt.Sub(event.StartAt) != 90*time.Minute || event.StartAt.Location() != time.UTC {
		t.Fatalf("normalize: %+v %v", event, err)
	}
	for _, change := range []func(*CalendarEventInput){
		func(in *CalendarEventInput) { in.Title = ptr(" ") },
		func(in *CalendarEventInput) { in.Title = ptr(strings.Repeat("ش", 201)) },
		func(in *CalendarEventInput) { in.StartAt = ptr("2026-11-27T10:00:00") },
		func(in *CalendarEventInput) { in.EndAt = in.StartAt },
		func(in *CalendarEventInput) { in.EndAt = ptr("2026-11-27T09:00:00Z") },
		func(in *CalendarEventInput) { in.EndAt = ptr("2026-12-09T09:00:00Z") },
		func(in *CalendarEventInput) { in.TimeZone = ptr("unknown/zone") },
		func(in *CalendarEventInput) { in.TimeZone = ptr("Local") },
	} {
		in := valid()
		change(&in)
		if err := in.apply(&CalendarEvent{}); err != ErrEventInvalid {
			t.Fatalf("invalid input accepted: %+v %v", in, err)
		}
	}
	for _, window := range [][2]string{{"", ""}, {"2026-11-27", "2026-11-28"}, {"2026-11-28T00:00:00Z", "2026-11-27T00:00:00Z"}, {"2026-01-01T00:00:00Z", "2026-12-31T00:00:00Z"}} {
		if _, _, err := ParseEventWindow(window[0], window[1]); err != ErrEventInvalid {
			t.Fatal("invalid window", window)
		}
	}
	if _, _, err := ParseEventWindow("2026-11-27T00:00:00+03:30", "2026-11-28T00:00:00+03:30"); err != nil {
		t.Fatal(err)
	}
}
