# Offline sync v1 — target contract and partial implementation status

Tracks #172, #21 and #239. **This is the target contract, not a description of a complete implemented API.** The existing incremental server implementation includes an owner-scoped change feed and an idempotent task-create path (`POST /api/v1/sync/tasks`), but does not implement the entire batch protocol below. The Android/Web durable mutation outbox, offline edit/delete, revision-conflict handling and end-to-end reconciliation are not yet complete. Do not enable offline mutation controls based on this document alone.

## Ownership and transport

- All endpoints require the existing authenticated account identity; never accept an owner ID from the body.
- Other owners' object IDs must return 404. A cursor, operation ID, or tombstone must not reveal another account's data.
- HTTPS only; no credentials, task bodies, or cursor contents in logs.
- All timestamps are UTC instants. The Flutter calendar renders them in the selected timezone/Jalali presentation without changing stored instants.

## Target batch API (not implemented as specified)

`POST /api/v1/sync` with `cursor` (opaque, nullable), `limit` (bounded, server-capped), and `operations` (bounded array). Each operation contains a UUID `operation_id`, entity type, stable entity ID, verb, expected entity revision, and validated payload. The response contains per-operation accepted/conflict/rejected results, an ordered page of owner-scoped changes including tombstones, and `next_cursor` plus `has_more`.

The cursor is bound to the authenticated owner, versioned, and authenticated against tampering. Invalid/expired cursors must return a stable machine-readable resync-required error, not silently skip changes. Full resync must preserve pending local operations and avoid resurrecting deleted records.

## Transactional guarantees

1. Record each `(owner_id, operation_id)` exactly once with a request digest and durable outcome in the same transaction as its mutation and change-feed entry.
2. Retrying an identical operation returns the stored outcome, even after a response is lost. Reusing an ID with a different payload returns a stable conflict error.
3. A mutation with a stale revision returns an explicit conflict and current owner-visible revision; it must not overwrite a newer value.
4. Delete creates a tombstone and increments revision. Late edits/completions cannot resurrect it.
5. Page changes by a stable monotonically ordered sequence; cursor advancement is atomic from the client's perspective. Never acknowledge an operation that was not durably committed.
6. Bound retention and pagination; publish the minimum supported offline duration. Expired cursors force a safe snapshot resync, not data loss.
7. Cross-account replay of operation IDs, cursors, or object IDs cannot read or modify another owner's records.

## Client ordering (future #21)

Keep the outbox encrypted or in platform-protected account-local storage; never delete pending commands merely because a request times out. Persist commands before optimistic UI success. On reconnect, replay with the same operation IDs, apply server outcomes and pages transactionally, then advance the local cursor. Switching account or signing out must isolate/wipe the former account's local private cache and outbox according to explicit sign-out semantics. Expired access tokens require a separately verified renewal mechanism (tracked by #195); do not assume a refresh-token flow exists. A network outage must not discard the saved session or pending commands.

## Required regression matrix

| Scenario | Expected result |
| --- | --- |
| Lost response then identical replay | One mutation, same outcome |
| Same operation ID, different payload | Conflict, no second mutation |
| Concurrent edits from two devices | Revision conflict, no silent overwrite |
| Complete after delete / edit after delete | Tombstone wins, no resurrection |
| Page boundary while writes arrive | No duplicate or skipped changes |
| Cursor tampering / expiry | Safe error and resync path |
| Cross-owner cursor and object ID | No data disclosure; object 404 |
| Interrupted transaction | No orphan idempotency record or feed event |
| Offline outbox during token refresh | Commands survive and retry |
| DST transition / Jalali display | UTC data unchanged, correct local rendering |

## Current implementation boundaries

- **Implemented incrementally:** server-side owner-scoped pull/change-feed and idempotent task creation via `POST /api/v1/sync/tasks`, with PostgreSQL regression coverage for replay, owner isolation, concurrent requests and pagination. These are separate endpoints; they are **not** the target batch `POST /api/v1/sync` contract.
- **Not complete:** durable client outbox, edit/delete mutation commands, revision-based conflict resolution, full cursor-expiry recovery and account-switch reconciliation. The complete offline-first experience remains blocked on #21/#239.
- **Session renewal:** #195 tracks Android session renewal; do not claim the target refresh-token mechanism exists without verifying its implementation and CI.
- **Validation:** any new endpoint, contract change or client behavior must have tests for ownership, replay, failures and recovery; successful historical CI runs do not validate future commits.

## Rollout gates

Implement a small API vertical slice with database migration, Go authorization/idempotency/replay tests and PostgreSQL integration tests first. Run existing Flutter format/analyze/tests and Android UI review for any client follow-up. Do not enable offline mutation controls until a durable outbox, conflict UI, rollback behavior and account-isolation tests exist. No schema deployment without backup/rollback review.
