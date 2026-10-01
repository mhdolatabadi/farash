# Tasks API (#5)

All routes require the account's bearer token. Tasks and project lookups are
owner-scoped; a missing or foreign object returns 404.

- `GET /api/v1/tasks?projectId=ID&showCompleted=true`: ordered project tasks.
  Completed tasks are hidden by default; deleted tasks are always hidden.
- `POST /api/v1/tasks`: `title` is required; optional `project_id` defaults to
  Inbox. `description` stores Markdown text, `priority` defaults to P4, and
  `sort_order` defaults to zero. Priorities are integers 1 through 4.
- `PATCH /api/v1/tasks/{id}`: update title, description, priority, order or
  project. Empty description clears it. Omitted fields stay unchanged.
- `POST /api/v1/tasks/{id}/close` and `/reopen`: set or clear `completed_at`.
  Repeated close preserves the original completion timestamp.
- `DELETE /api/v1/tasks/{id}`: soft-delete, retaining fields and timestamps.
- `POST /api/v1/tasks/{id}/restore`: undo a soft deletion, preserving identity,
  project, completion, description and priority. Only deleted tasks can restore.
- `POST /api/v1/tasks/reorder`: `{ "project_id": "ID", "task_ids": [...] }`.
  A unique subset of 1–1000 visible task IDs gets contiguous order values.
  Every ID must belong to that account and project and be undeleted. Failed
  requests write nothing. Completed tasks can be included explicitly.

Create/move targets must be active projects, not folders. Existing tasks in an
archived project remain readable and editable; moving new tasks into it is
refused. Project deletion cascades to its tasks, including deleted history;
restoration applies to task deletion while its containing project exists.

Task titles are trimmed and limited to 500 characters. Descriptions are limited
to 20,000 characters. JSON write bodies have a 128 KiB limit, reject unknown
fields and trailing JSON. These are ordinary authenticated CRUD routes; auth
rate limiting remains on register/login. Task content is never logged.

## Migration and rollback

Migration 004 adds a new table without rewriting existing data. Deploy through
repository CI/workflows. Roll back application code first if necessary; the
extra table can remain safely. Do not drop `tasks` after users have created data.

## Remaining client work

The Flutter quick-add, detail sheet, colored flags, completion/delete undo,
completed-task toggle and drag reordering are tracked by #5. This API change
does not close that issue.
