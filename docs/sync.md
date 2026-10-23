# Core-data sync feed (#99, foundation for #21)

This delivers a read-side server foundation. It does not enable offline editing,
local persistence, command replay, reminders or widgets in the shipped clients.
The existing HTTP write APIs remain authoritative. Parent #21 stays open.

## Protocol v1

Authenticated `POST /api/v1/sync` takes `{"cursor":"","limit":100}`.
An empty cursor starts bootstrapping; limit defaults to 100 and must be 1–500.
Response: `version`, `cursor`, `has_more`, and `changes`.
Each change has `entity`, `id`, decimal-string `revision`,
`operation` (upsert/delete), and `data` (row image or null tombstone).
Apply returned rows atomically to a staging cache, save the returned cursor with
them, and continue while has_more. Do not announce a complete bootstrap until
all pages have been applied. A page can contain part of a server transaction;
a relational cache must stage links or defer constraint validation until the
batch is drained. There is no transaction-grouping guarantee in protocol v1.

The cursor is versioned and owner-bound, not an authorization credential.
A foreign, malformed or future cursor returns 400. Authenticate each request.
Revisions are strings to avoid JavaScript integer precision loss. Treat entity
IDs as opaque; task-label IDs are a JSON array of task and label IDs.

The initial registry is projects, sections, tasks, labels, task_labels and
time_entries. Payloads are database row images, not the existing task DTO:
due_date/due_at/due_timezone and deleted_at remain explicit; derived subtask
counts are recomputed by clients. owner_id and time request_key are omitted.
Credentials, users, auth tokens and emails are never registered. Project method
is included in the project row; sprint/recurrence/membership metadata is not.
Unknown entity support and additional registries require a deliberate protocol
extension before a client can claim a complete account cache.

## Consistency and deletion

Migration 014 installs AFTER triggers and seeds all existing rows in one
transaction. Every write allocates the next owner-local revision under a
transactional row lock. The corresponding state update and revision commit or
roll back together. A reader cannot skip a transaction which committed after a
higher globally allocated sequence; there is no global sequence cursor.

Only the latest version per entity is retained. Repeated edits coalesce;
there is no edit-history/audit guarantee. Reads use a repeatable-read snapshot.
Edits arriving while a client drains pages move to a newer revision and are
returned on a later page/poll. Reapplying an unchanged page is safe when clients
compare entity revisions. Never advance a cursor before committing its rows.

Soft deletion and completion are ordinary task upserts, including their actual
timestamps; hard deletion emits a null-data tombstone. Tombstones remain until
account deletion, so old devices cannot resurrect physically deleted rows.
There is no pruning/token-expiry policy yet. All sync metadata cascades on
account deletion. The feed remains strictly owner-scoped: accepting a project
invitation does not silently grant this endpoint access to another owner.

The revision lock serializes writes for one account. Existing multi-row writers
can still encounter normal PostgreSQL transaction deadlocks; failed writes must
be retried as whole requests under their established idempotency contracts.
Do not swallow a trigger failure or emit an acknowledged write without its sync
record.

## Next required work and rollback

Before offline-first can ship: durable encrypted/account-isolated client storage
where supported, command IDs with server idempotency, per-field conflict and
completion rules, command replay/recovery, wipe on sign-out/account switch,
bootstrap staging, new model registration and reconnect UI. Reminders (#14) and
widgets (#26) cannot read this network endpoint as a substitute for local data.

For additional owner-scoped tables, add an explicit migration/backfill and
trigger registration; do not register users or secret-bearing tables wholesale.
Child tables without owner_id need their own stable owner derivation and must
emit tombstones even during parent cascades. Shared data requires revocation
events and separate authorization design before inclusion.

Migration is additive; rollback code may leave sync tables and triggers intact.
Do not drop tombstones or reset revisions while clients retain cursors.
Database restore to an earlier revision invalidates a later client cursor
(400); the client must explicitly rebuild its cache without discarding queued
intent. Current clients do not yet consume this endpoint.

Tests cover bounded paging, owner binding/isolation, edits, completion/soft
delete, hard-delete tombstones, account deletion, uncommitted writes, concurrent
commits, rollback and sanitized API failures. CI supplies PostgreSQL execution;
the editing session has no local runtime, so no local execution is claimed.
