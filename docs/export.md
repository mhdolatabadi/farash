# Portable JSON export, version 1 (#97)

Authenticated `GET /api/v1/export` downloads `farash-export-v1.json`. Web and Android expose this under account/settings → خروجی داده‌های من. Import/restore, Todoist/TickTick conversion, CSV and templates remain in #24/#76.

The response is a JSON object:
- `format`: `farash-export`
- `version`: integer `1`
- `exported_at`: RFC3339 transaction timestamp
- `preferences`: stored weekly active-day and task goals
- `records`: arrays named `projects`, `sections`, `tasks`, `labels`, `task_labels`, `time_entries`, `sprints`, `scrum_items`, `sprint_scope`, `sprint_events`.

Version 1 explicitly includes the fields supported at migration 011. IDs and foreign-key IDs are preserved within the snapshot; consumers must treat IDs as opaque strings (event IDs are numbers) and remap them if importing into another account. Arrays are stable and empty arrays are `[]`. Fields use the database names documented in migrations 003–011, except `owner_id`, which is omitted. Date-only values use Gregorian ISO civil dates; timestamps include an offset. Preserve `due_timezone` to distinguish the planned zone from a UTC instant. No UI locale conversion occurs in the portable document.

Archived projects, completed tasks, soft-deleted tasks and task hierarchy are included. Completed-task history is the task completion timestamps actually stored, not a fabricated occurrence/activity log. Scrum scope snapshots can reference a task that no longer exists; do not discard those rows. Closed tracked time, notes, scope events and time entries are exported as stored. Running time entries retain a null end; consumers must not invent a stop time.

This is not a PostgreSQL dump or a promised one-click restore format. It excludes credentials/password hashes, email, tokens, server secrets, client-local preferences/assets and all other accounts' records. Future data categories such as recurrence, attachments, habits or collaboration require a documented format extension before export coverage is claimed. Consumers should reject unsupported versions and preserve unknown fields when possible.

All reads use one read-only repeatable-read transaction. The caller cannot supply an owner or arbitrary table. No server-side export file is retained. Responses prohibit caching and use a fixed attachment filename. Each account may request two downloads per minute per API process. Exports are limited to 100,000 records total, 32 MiB encoded JSON and a 15-second database operation deadline. A limit produces `413 export_too_large`; it never returns a truncated successful document. Timeout produces `503 export_unavailable`, other storage failures `500 export_unavailable`. Query parameters produce `400 invalid_export_query`; an invalid/missing session produces `401`. Larger account exports require a future paginated/streaming format, not silent omission.

No migration is needed. Rollback removes the route and new files; existing records remain untouched. Treat downloaded task content as private.


## Client download (#108)

The client first prepares the authenticated JSON document, then waits for a separate explicit save action. This preserves browser download activation and lets the user choose an Android destination through the system document provider (`ACTION_CREATE_DOCUMENT`). No broad storage permission, persisted URI permission, cached private file or background upload is added. Android writes off the UI thread. Cancellation retains only the in-memory payload for retry; closing the dialog releases it. A failed write can leave an incomplete user-selected document, so retry or remove that file. Browser feedback says only that the download was handed to the browser, never that a file-system write was confirmed.

The client accepts only version 1 with the expected top-level envelope, reads at most 32 MiB, and bounds the operation at 30 seconds. It does not transform IDs, dates, unknown fields or JSON bytes. It rechecks the current account token before exposing or saving prepared data. Closing during preparation never starts a save. The Android document provider may independently retain the chosen file; exported data is outside sign-out cleanup once deliberately saved. The synthetic native fixture contains no account data and demonstrates document-picker cancellation; actual production-account export and third-party document-provider behavior remain separate manual checks.
