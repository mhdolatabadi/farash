# Recurrence engine contract (#54, part of #10)

This pure server package calculates occurrences. It does not attach a rule to a
stored task, complete a task, write history, or expose an API/editor yet.

A schedule contains its first due date (`YYYY-MM-DD`, Gregorian wire format),
optional local `HH:mm`, an explicit IANA timezone, and a structured rule. Rules
use `day`, `week`, `month`, or `year`, interval 1–1000, calendar `gregorian` or
`jalali`, and basis `due` or `completion`. Selected weekdays are Sunday=0 through
Saturday=6. Weekly buckets start on Saturday. Monthly selectors are either a
fixed day 1–31 or the last chosen weekday; absent selectors inherit the anchor
month/day. Only weekly rules accept weekdays and only monthly rules accept a
monthly selector. Unknown enum values, duplicates, conflicting selectors,
invalid dates/times/zones and irrelevant fields are rejected.
The initial due date must match any selectors (including a clamped fixed day),
and a timed initial due must exist in its timezone. Count is bounded at 1,000,000.

`Next(schedule, after, emitted)` advances after a completion/skip. `emitted`
counts occurrences already issued, including the first (minimum 1). A count of
zero in the rule means unlimited; maximum count 1 ends after the first. Missed
slots and nonexistent DST wall times do not consume the count. The optional
inclusive end date is a Gregorian local date in the schedule timezone. Supported
wire dates are 1900-01-01 through 2199-12-31, matching task due validation.

Due-based repeats remain anchored to the original start and return the first
eligible occurrence strictly after both start and `after`. Late completions skip
missed slots; they do not create a backlog. Completion-based repeats re-anchor
to the local completion day, preserving the schedule's chosen wall time. They
advance at least one interval; selected weekdays use the next eligible weekly
bucket, monthly selectors the next eligible month. Early completion is allowed.

Calendar arithmetic uses civil days, not elapsed 24-hour durations. Weekly rules
without selectors retain the anchor weekday. Monthly/yearly short-month dates
clamp to the final day and always derive from the original anchor: January 31
→ February 28 → March 31. Jalali rules use Solar Hijri month lengths and leap
years, with the same break-table algorithm as `lib/core/calendar/jalali.dart`.
Yearly rules preserve the anchor month and clamp its day.

Timed occurrences preserve local hour/minute. A DST gap skips that occurrence;
a repeated wall time chooses its earliest UTC instant. Whole-day occurrences
remain dates, with no invented timestamp. Exhaustion (end/count/date range)
returns no occurrence; malformed input returns an explicit error. The engine
reads no system clock and mutates no input.

Future integration under #10 must atomically advance a task, record completion
history, implement skip/undo and retries, retain the immutable anchor and emitted
counter, enforce owner checks, and add the client recurrence editor.
