# Offline sync v1 — proposed contract (not implemented)

Tracks #172 and #21. This document is a design gate, **not** a claim that offline writes work. No client should enqueue production mutations until the API and persistence tests described here pass.

## Ownership and transport

- All endpoints require the existing authenticated account identity; never accept an owner ID from the body.
- Other owners' object IDs must return 404. A cursor, operation ID, or tombstone must not reveal another account's data.
- HTTPS only; no credentials, task bodies, or cursor contents in logs.
- All timestamps are UTC instants. The Flutter calendar renders them in the selected timezone/Jalali presentation without changing stored instants.

## Proposed API

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

Keep the outbox encrypted or in platform-protected account-local storage; never delete pending commands merely because a request times out. Persist commands before optimistic UI success. On reconnect, replay with the same operation IDs, apply server outcomes and pages transactionally, then advance the local cursor. Switching account or signing out must isolate/wipe the former account's local private cache and outbox according to explicit sign-out semantics. Expired access tokens should renew through the existing refresh-token flow; a network outage must not log out the user.

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

## Rollout gates

Implement a small API vertical slice with database migration, Go authorization/idempotency/replay tests and PostgreSQL integration tests first. Run existing Flutter format/analyze/tests and Android UI review for any client follow-up. Do not enable offline mutation controls until a durable outbox, conflict UI, rollback behavior and account-isolation tests exist. No schema deployment without backup/rollback review.
