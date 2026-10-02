# Due dates, deadlines and durations

Tracks [#8](https://github.com/mhdolatabadi/farash/issues/8).

## Task fields

```json
"due": {"date": "2026-10-06", "datetime": "2026-10-05T21:00:00Z", "timezone": "Asia/Tehran"},
"deadline": "2026-10-10",
"duration_minutes": 45
```

- `due` is `null`, an all-day `{"date"}`, or a moment. A moment is stored in
  UTC together with the IANA zone it was planned in, and `date` is its local
  day in that zone. The example above is 00:30 on 6 October in Tehran.
- `deadline` is a separate `YYYY-MM-DD` day.
- `duration_minutes` (1–1440) needs a timed due.
- Dates must fall between 1900 and 2199. Every zone is embedded in the binary
  (`time/tzdata`), so a slim image still knows `Asia/Tehran`.

## Writing

- **POST /api/v1/tasks** takes `due` (`{"date"}` or `{"datetime","timezone"}`),
  `deadline` and `duration_minutes`.
- **PATCH /api/v1/tasks/{id}:**
  - An absent field stays as it is, `null` clears it, and a value sets it.
  - Clearing the due, or making it all-day, also clears the duration unless
    the same request sends one.
- **POST /api/v1/tasks/reschedule** takes
  `{"task_ids": [...], "due": {...} | null}`:
  - Sets one due on up to 500 of the caller's tasks in one transaction and
    returns them in the order sent.
  - Other fields stay as they are, except the duration, which is dropped when
    the new due has no time.
  - Any missing or foreign ID answers `404 task_not_found`, and nothing
    changes.

Errors: `invalid_due`, `invalid_deadline`, `invalid_duration` and
`invalid_task_ids` (all 400). A date sent together with a moment must be that
moment's local day.

## Calendar in the app

The app shows dates in the Jalali calendar by default, with Persian digits
and weekday names; weeks start on Saturday. Both are per-device settings
until account settings arrive in #25.

## Migration and rollback

`007_add_due_dates.sql` adds five nullable columns, three checks and a
partial index. Existing tasks have no dates. To roll back:

```sql
DROP INDEX IF EXISTS tasks_owner_due;
ALTER TABLE tasks DROP COLUMN duration_minutes, DROP COLUMN deadline, DROP COLUMN due_timezone, DROP COLUMN due_at, DROP COLUMN due_date;
DELETE FROM schema_migrations WHERE version = 'migrations/007_add_due_dates.sql';
```
