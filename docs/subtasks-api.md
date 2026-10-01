# Subtasks and checklists

Tracks [#7](https://github.com/mhdolatabadi/farash/issues/7).

## Model

- `tasks.parent_id` makes a task a subtask of another task of the same owner
  (`(owner_id, parent_id)` → `tasks (owner_id, id)`, `ON DELETE CASCADE`).
- A subtree always shares its top task's project and section. The store keeps
  this when a parent moves: its subtasks move with it.
- Up to five levels (a task with four levels of subtasks below it). Cycles,
  self-parenting and deeper trees answer `400 invalid_parent`.
- Every task response carries `parent_id`, `subtask_count` and
  `completed_subtask_count` (live direct subtasks), so a list without
  completed tasks can still show progress such as ۲/۵.

## API

| Request | Effect |
| --- | --- |
| `POST /api/v1/tasks` with `parent_id` | Creates a subtask in the parent's project and section. A different `project_id` or `section_id` → `400 invalid_parent`; a completed parent → `400 invalid_parent`. |
| `PATCH /api/v1/tasks/{id}` with `parent_id: "<id>"` | Indent: moves the task and its subtree under that task. |
| `PATCH /api/v1/tasks/{id}` with `parent_id: ""` | Outdent to top-level; project and section stay. |
| `PATCH` with a new `project_id` or `section_id` and no `parent_id` | The subtask becomes top-level in the new place. Other edits keep the parent. |
| `POST /api/v1/tasks/{id}/close` | Closes the task and its open subtasks with the same `completed_at`. |
| `POST /api/v1/tasks/{id}/reopen` | Reopens the task, the subtasks that closed together with it (same `completed_at`), and any completed ancestors. Subtasks closed on their own stay closed. |
| `DELETE /api/v1/tasks/{id}` | Soft-deletes the task and its live subtasks with the same `deleted_at`. |
| `POST /api/v1/tasks/{id}/restore` | Restores the task and the subtasks deleted together with it. If its parent is still deleted, or completed while the task is open, it comes back top-level. |

A parent that is not the caller's, is deleted or does not exist answers
`404 parent_not_found`. Order among siblings uses the existing
`POST /api/v1/tasks/reorder`.

Hierarchy changes take a per-owner advisory transaction lock, so two
concurrent moves cannot both pass the cycle check and form a loop.

## Checklists

TickTick-style checklist items live in the description as Markdown task
lines, `- [ ] open` and `- [x] done`, so they need no schema and stay
readable anywhere Markdown is. The app ticks them in place and saves the
description at once.

## Migration and rollback

`006_add_subtasks.sql` adds a unique `(owner_id, id)` key, the nullable
`parent_id` column, its foreign key, a not-self check and a partial index.
Existing tasks keep `parent_id = NULL`. To roll back (losing nesting only):

```sql
ALTER TABLE tasks DROP CONSTRAINT tasks_parent_fk, DROP CONSTRAINT tasks_parent_not_self, DROP COLUMN parent_id;
DROP INDEX IF EXISTS tasks_owner_parent;
ALTER TABLE tasks DROP CONSTRAINT tasks_owner_id_id_key;
DELETE FROM schema_migrations WHERE version = 'migrations/006_add_subtasks.sql';
```
