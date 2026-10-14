package recurrence

import (
	"testing"
	"time"
)

func TestJalaliKnownDates(t *testing.T) {
	for _, tt := range []struct {
		gregorian        string
		year, month, day int
	}{
		{"2024-03-20", 1403, 1, 1}, {"2025-03-20", 1403, 12, 30},
		{"2025-03-21", 1404, 1, 1}, {"2026-03-21", 1405, 1, 1},
		{"2026-09-23", 1405, 7, 1}, {"2026-10-01", 1405, 7, 9},
		{"1979-02-11", 1357, 11, 22}, {"2000-01-01", 1378, 10, 11},
	} {
		day, _ := parseDate(tt.gregorian)
		y, m, d := calendarDate(day, Jalali)
		if y != tt.year || m != tt.month || d != tt.day {
			t.Errorf("%s = %d/%d/%d; want %d/%d/%d", tt.gregorian, y, m, d, tt.year, tt.month, tt.day)
		}
	}
}

func TestJalaliEntireSupportedRange(t *testing.T) {
	for date := time.Date(1900, 1, 1, 0, 0, 0, 0, time.UTC); date.Year() < 2200; date = date.AddDate(0, 0, 1) {
		y, m, d := calendarDate(date, Jalali)
		length := monthLength(y, m, Jalali)
		if m < 1 || m > 12 || d < 1 || d > length {
			t.Fatalf("invalid Jalali day for %s: %d/%d/%d", date, y, m, d)
		}
		gy, march, _ := jalaliYear(y)
		offset := (m-1)*31 + d - 1
		if m > 7 {
			offset -= m - 7
		}
		roundTrip := time.Date(gy, 3, march, 0, 0, 0, 0, time.UTC).AddDate(0, 0, offset)
		if !roundTrip.Equal(date) {
			t.Fatalf("round trip %s -> %d/%d/%d -> %s", date, y, m, d, roundTrip)
		}
		if date.Year() == 2199 && date.Month() == 12 && date.Day() == 31 {
			break
		}
		ny, nm, nd := calendarDate(date.AddDate(0, 0, 1), Jalali)
		wantY, wantM, wantD := y, m, d+1
		if d == length {
			wantD = 1
			wantM++
			if wantM == 13 {
				wantY++
				wantM = 1
			}
		}
		if ny != wantY || nm != wantM || nd != wantD {
			t.Fatalf("noncontiguous at %s", date)
		}
	}
}
