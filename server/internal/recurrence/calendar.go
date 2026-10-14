package recurrence

import "time"

// The same jalaali-js break table and truncating integer arithmetic used by
// lib/core/calendar/jalali.dart. Supported task dates lie within its range.
var jalaliBreaks = [...]int{-61, 9, 38, 199, 426, 686, 756, 818, 1111, 1181, 1210, 1635, 2060, 2097, 2192, 2262, 2324, 2394, 2456, 3178}

func jalaliYear(year int) (gregorian, march, leap int) {
	gregorian = year + 621
	leapJ, previous, jump := -14, jalaliBreaks[0], 0
	for _, next := range jalaliBreaks[1:] {
		jump = next - previous
		if year < next {
			break
		}
		leapJ += jump/33*8 + (jump%33)/4
		previous = next
	}
	n := year - previous
	leapJ += n/33*8 + (n%33+3)/4
	if jump%33 == 4 && jump-n == 4 {
		leapJ++
	}
	leapG := gregorian/4 - (gregorian/100+1)*3/4 - 150
	march = 20 + leapJ - leapG
	if jump-n < 6 {
		n = n - jump + (jump+4)/33*33
	}
	leap = ((n+1)%33 - 1) % 4
	if leap == -1 {
		leap = 4
	}
	return
}

func civilDate(t time.Time) time.Time {
	return time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, time.UTC)
}

func daysBetween(a, b time.Time) int {
	// Both inputs are UTC civil dates, never instants in a DST zone.
	return int((b.Unix() - a.Unix()) / 86400)
}

func calendarDate(day time.Time, calendar Calendar) (year, month, date int) {
	if calendar == Gregorian {
		return day.Year(), int(day.Month()), day.Day()
	}
	year = day.Year() - 621
	gy, march, _ := jalaliYear(year)
	start := time.Date(gy, 3, march, 0, 0, 0, 0, time.UTC)
	if day.Before(start) {
		year--
		gy, march, _ = jalaliYear(year)
		start = time.Date(gy, 3, march, 0, 0, 0, 0, time.UTC)
	}
	delta := daysBetween(start, day)
	if delta < 186 {
		return year, delta/31 + 1, delta%31 + 1
	}
	delta -= 186
	return year, delta/30 + 7, delta%30 + 1
}

func monthLength(year, month int, calendar Calendar) int {
	if calendar == Gregorian {
		return time.Date(year, time.Month(month)+1, 0, 0, 0, 0, 0, time.UTC).Day()
	}
	if month <= 6 {
		return 31
	}
	if month < 12 {
		return 30
	}
	_, _, leap := jalaliYear(year)
	if leap == 0 {
		return 30
	}
	return 29
}
