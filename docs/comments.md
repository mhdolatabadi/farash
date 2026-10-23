# Private comment API

This slice of #15 stores text/Markdown source on a task or regular project.
It does not render HTML, upload attachments, grant shared access or send notifications.

`GET /api/v1/{tasks|projects}/{target}/comments` returns up to 50 records,
`total` live comments and `next` (pass as `after`). Pagination is ordered by
creation timestamp and ID. Deletion retains a content-free tombstone, so an
existing cursor remains valid. Each response is a consistent read snapshot.

Create with `POST` and `{body, request_key}`; edit with `PATCH .../{comment}`
and `{body}`; delete with `DELETE .../{comment}`. A key is private per account,
8–120 ASCII letters/digits/underscores/hyphens. Retrying a create uses the same
key and original body/target; changing either is a conflict. Edits do not change
the original create fingerprint. Deleted content is cleared, not restored by a retry.

Bodies accept 1–16000 Unicode characters after trimming. A target has at most
5000 historical comments (including tombstones). Mutations are limited to 30
per minute/account/process; multi-instance global rate limiting is not claimed.
Archived targets remain readable and reject writes. Foreign/missing/deleted
targets return 404. Parent project/task deletion and account deletion cascade.

A changed task comment also updates the task version. This prevents recurring
undo from deleting a successor that acquired comment history, including a comment
that was subsequently edited or deleted. An idempotent create retry does not
update the task version; edits and deletes conservatively update it, including
a repeated delete. Project comments do not update a
task version.

Migration 018 is additive. Preserve its table during code rollback to retain
comments. This API is owner-only until a complete shared authorization policy
is integrated. The client editor, row counts, notifications, attachment storage,
export and sync registry support remain follow-up work; #15 stays open.
