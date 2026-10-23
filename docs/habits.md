# Habit tracker (#20)

Habits follow Loop Habit Tracker's model and screens. They are private, owner-scoped records separate from tasks, rugs and XP.

## Model

- A habit is **yes/no** or **measurable** (amount with a unit, an at-least or at-most target per day, week or month). The kind is fixed at creation.
- Yes/no frequencies are Loop's: every day, every week, N times per week, or a custom N times in D days (1 ≤ N ≤ D ≤ 365).
- Each day is unknown (no row), done (`value` 1), not done (`value` 0), skipped (`skip`), or an amount for measurable habits. Days are local calendar dates sent as `YYYY-MM-DD`; the server rejects days before 2000 and after tomorrow in UTC, which leaves room for every time zone's today.
- Colors are Loop's 20-color palette by index, with lighter variants in dark mode.

## Derived values (client, `habit_stats.dart`)

Ported from Loop's `ScoreList`, `EntryList` and `StreakList`:

- **Automatic checks**: for a non-daily yes/no habit, every N check-ins within D days mark the interval as done (lighter check). Intervals are snapped together as in Loop. One deliberate difference: an explicit "not done" stays visible inside such an interval, so a tap always shows its result.
- **Strength**: Loop's exponential score, `multiplier = 0.5^(√frequency / 13)`, fed by a rolling window of the last D days. Non-daily yes/no habits double N and D to smooth irregular weeks. Skipped days leave the score unchanged. At-most habits start at 100%.
- **Streaks**: consecutive days that are done, automatically checked or skipped. A daily measurable target must be met that day; weekly and monthly targets count any progress. Today being still open keeps yesterday's streak current.
- History returned with each habit covers the last five years; older days have decayed to nearly nothing in the score.

## Screens

- **List**: flat rows separated by hairlines, a strength ring and the habit's colored name, then a column per recent day with today next to the name. The number of columns follows the width (1–7). Tap a yes/no day to cycle unknown → done → not done → skipped → unknown; tap a measurable day to type an amount (Persian or Latin digits, `٫` or `.` decimals). Long press and drag reorders in manual order. The filter menu shows archived habits and sorts by manual order, name, color or strength. One FAB adds a habit; the list keeps bottom clearance so it never covers the last row.
- **Detail**: overview (strength, change against a month and a year ago, total, current streak), target progress for measurable habits, strength chart and history bars by day/week/month/quarter/year, a 26-week calendar where tapping a day records it, best streaks and the weekday-by-month frequency chart. Charts run left to right in time and open on the newest period at the right, matching the list's day columns. Archive and delete are in the overflow menu; delete asks first and suggests archiving.
- **Editor**: Loop's flow, choosing yes/no or measurable first. Reminders are not offered yet; they depend on the notification work in #14.

Check-ins are optimistic and roll back with a snackbar when the server refuses them. Weeks start on the calendar setting's weekday and dates follow the Jalali/Gregorian choice.

## API

All routes require a bearer token; another owner's habit answers 404.

| Method | Path | Body | Result |
|---|---|---|---|
| GET | `/api/v1/habits` | | `{habits: [habit + entries]}` in manual order |
| POST | `/api/v1/habits` | habit fields | `201 {habit}` |
| PATCH | `/api/v1/habits/{id}` | changed fields, `archived` | `{habit}` |
| DELETE | `/api/v1/habits/{id}` | | `{deleted: true}` (entries cascade) |
| POST | `/api/v1/habits/reorder` | `{habit_ids}` | `{reordered: true}` |
| PUT | `/api/v1/habits/{id}/entries/{day}` | `{value, skip}` | `{entry}` |
| DELETE | `/api/v1/habits/{id}/entries/{day}` | | `{deleted: true}` (idempotent) |

Errors: `invalid_habit`, `invalid_habit_entry` (400), `not_found` (404), `habit_limit_reached` (409, 200 habits per account including archived).

Migration `020_habits.sql` is additive (two new tables). Rolling the client or API back leaves the tables in place; never drop them as a rollback.
