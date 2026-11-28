# Native calendar events

An event belongs to one account and is independent of tasks and provider
calendars. Google calendar connections retain their read-only scopes.

`/api/v1/events` lists, creates, updates and soft-deletes events. The authenticated
owner is applied to every query, including retry lookups and restoration. Foreign
IDs return404. Mutations are rate-limited; responses are private/no-store.

Titles are trimmed and contain1–200 Unicode characters. Start/end must be RFC3339
instants with an offset; the end is strictly later than the start. Years are
2000–2200, spans at most seven days, and the IANA timezone must be recognized.
List windows have exclusive end bounds and are at most93 days; events crossing the
start of the window are included. More than1000 results returns an explicit limit
error instead of silently hiding events.

Creation carries a stable request key. A lost response can replay the same create
without inserting a second event. If input changed, the client first recovers that
create, then updates its confirmed ID. Edits carry a version and conflicts return
409. The form retains input and explains that the event must be refreshed.
Deletion preserves the record; its snackbar offers restoration. No recurrence,
notifications or provider writes are introduced.

The UI initially creates a timed same-day event on the selected visible date.
The device timezone determines displayed wall times, matching scheduled tasks;
UTC instants and the event's timezone are stored. Existing overnight events keep
their day offset when edited, split at local midnight, and use shared collision
lanes alongside tasks. Invalid or nonexistent local wall times are rejected.

## Deployment and rollback

The additive migration runs through the existing transactional migration table.
Deploy through repository workflows after required checks pass. Deploy the API
before using the new client event functionality. Rolling back client/API code
must retain both native-event tables; older code ignores them and user data stays
intact. Do not drop event records to roll back a UI release.
