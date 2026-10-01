# Sections API (#6)

Sections split a project into named groups. All routes require the account's
bearer token. Sections are owner-scoped; a missing or foreign section answers
`404 section_not_found`, and a missing, foreign or folder project answers
`404 project_not_found`.

- `GET /api/v1/sections?projectId=ID`: `{"sections": [...]}` in order.
- `POST /api/v1/sections`: `{"project_id", "name"}` adds a section after the
  others. The project must be active and not a folder.
- `PATCH /api/v1/sections/{id}`: `{"name"?, "is_collapsed"?}`.
- `POST /api/v1/sections/reorder`: `{"project_id", "section_ids": [...]}`;
  1–500 unique IDs of that project's sections get contiguous order values.
- `DELETE /api/v1/sections/{id}`: the section's tasks stay in the project
  without a section. With `?deleteTasks=true` they are soft-deleted instead
  and can still be restored (without the section).

Names are trimmed, one line, 1–120 characters (`400 invalid_section`).
Deleting a project deletes its sections.

## Tasks in sections

Tasks have a nullable `section_id`.

- `POST /api/v1/tasks` takes an optional `section_id`. Without `project_id`
  the task goes to the section's project; with a different `project_id` the
  request fails with `400 invalid_section`.
- `PATCH /api/v1/tasks/{id}` takes `section_id`: an ID moves the task into
  that section of its (new) project, `""` takes it out of its section. Moving
  a task to another project without a `section_id` also takes it out.
- Order within a section is the tasks' `sort_order`; reorder a section's
  tasks with `POST /api/v1/tasks/reorder`.

## Migration and rollback

Migration 005 adds the `sections` table and the nullable `tasks.section_id`
column without rewriting existing rows. Deleting a section clears only
`section_id` on its tasks (`ON DELETE SET NULL (section_id)`, PostgreSQL 15+).
Roll back application code first if needed; the table and column can stay.
