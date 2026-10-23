# External calendar connections

Implementation contract for [#119](https://github.com/mhdolatabadi/farash/issues/119), complementary to the local calendar/time-blocking work in #17. **No calendar provider is connected by this document.** No endpoint, migration, credential handling or connection UI below exists yet.

## Delivery boundaries

Google Calendar is the first provider. The first usable release reads selected calendars and overlays their events beside tasks. It does not create tasks from events, edit provider events, invite attendees, send notifications or award rewards. Outlook and CalDAV need separate adapters and provider-specific consent/sync tests. An outbound secret ICS feed is a different feature.

Use provider-neutral connection/calendar/event identifiers internally; never expose raw provider IDs as an authorization mechanism. Keep existing task, recurrence, time and Scrum models independent. Two-way synchronization needs a separate mapping, conflict and deletion contract before requesting write scopes.

## Authorization and deployment

Use a server-brokered Google web-server authorization-code flow for both clients. The API owns the confidential OAuth client and token exchange. Web opens Google's consent page; Android opens the system browser and returns through a verified HTTPS App Link. Do not embed a web view, provider secret or refresh token in Flutter. This is not the desktop loopback flow.

Request only `calendar.calendarlist.readonly` and `calendar.events.readonly` (full URI prefix `https://www.googleapis.com/auth/`). Explain that Google grants access at account scope, while Farash fetches only calendars the user selects. Request offline access for background refresh; do not repeatedly force consent to obtain a refresh token. Missing refresh credentials produce a recoverable reconnect state, not a falsely connected background-sync state. Do not overwrite an existing refresh token when a successful refresh omits one. [OAuth] [Scopes]

Farash requirements:

- Start is authenticated and rate-limited. Generate 256-bit random, single-use state; persist its hash, owner, expiry (10 minutes), selected client and a fixed return destination. Bind it to a browser correlation cookie (`Secure`, `HttpOnly`, `SameSite=Lax`) on the broker origin. Android first opens a one-use broker start ticket so this cookie can be set without sending the Farash bearer token in a URL.
- Use S256 PKCE when supported by the selected provider/client flow; keep the verifier server-side and erase it after exchange. The Google web-client PKCE capability must be proved by a sandbox callback test before release; state/cookie validation is mandatory regardless. Never substitute a desktop OAuth client for Android.
- Callback checks state, correlation, expiry and provider before atomically consuming the attempt. Reject replay, denied consent, missing required scopes and unknown owner. Never take owner IDs or arbitrary return URLs from callback input.
- Success redirects to a fixed Web route or verified Android App Link carrying an opaque, short-lived completion identifier only. The authenticated app fetches status; no tokens, provider code or calendar data pass through the handoff. Browser cancellation/process death can resume status from the account connection screen.
- Exchange and provider requests have explicit timeout/response-size limits and fixed provider origins. Redact query strings on callback/access logs and never log codes, state, tokens, event text or private links.
- Access/refresh tokens use authenticated encryption at rest with a versioned key ID and connection/owner-bound associated data. Keep encryption keys outside PostgreSQL/source; document rotation and backup restoration. Serialize refresh per connection and reject stale writes using a generation fence.

Proposed configuration is disabled by default: `CALENDAR_GOOGLE_ENABLED`, client ID/secret, exact public HTTPS callback URI, fixed allowed Web/App-Link return origins and token-encryption key ring. Enabling with incomplete configuration must fail startup without printing values. No production key or Google registration is created here. OAuth consent/verification, privacy URL and Android signing/App-Link ownership are release prerequisites. [OAuth] [Scopes]

## Proposed API and storage

All routes except the provider callback require Farash authentication. Every connection/calendar/event query is owner-scoped; missing and foreign identifiers return 404. Responses use opaque Farash IDs. Tokens and provider sync cursors never enter client responses or account JSON exports.

| Route | Proposed behavior |
| --- | --- |
| `GET /api/v1/calendar-connections` | Status and last successful refresh; no credentials. |
| `POST /api/v1/calendar-connections/google/authorize` | One-use start URL; fixed `web` or `android` client. |
| `GET /calendar-authorize/start?ticket=` | Consume one-use broker ticket, set correlation cookie, redirect to Google; no bearer token in URL. |
| `GET /api/v1/calendar-connections/google/callback` | Validated provider callback; no authenticated bearer token expected. |
| `GET /api/v1/calendar-connections/{id}/calendars` | Paginated provider calendar choices, no event fetch before selection. |
| `PUT /api/v1/calendar-connections/{id}/selection` | Replace selected opaque calendar IDs with optimistic version check. |
| `POST /api/v1/calendar-connections/{id}/refresh` | Coalesced refresh job; 202, never a blocking full account import. |
| `GET /api/v1/calendar-events?from=&to=&cursor=` | Bounded completed snapshots plus freshness/loading status. |
| `DELETE /api/v1/calendar-connections/{id}` | Disable and fence workers, delete local credentials/cache, attempt remote revocation. |

Proposed additive tables (migration number reserved only at implementation): owner-scoped `calendar_connections` (provider, encrypted credentials, generation, status); `connected_calendars` (provider ID, selection, time zone, sync cursor); `calendar_event_resources` (master/exception, provider event ID and etag); `calendar_event_windows` (completed bounded instances); short-lived authorization attempts and refresh jobs. Uniqueness is per connection + calendar + provider event ID. Do not deduplicate separate calendars/accounts by `iCalUID` or event title.

Disconnect takes effect locally even if the provider is unreachable: fence first, then erase local data. Remote revocation may be reported unsuccessful, with a Google account-permissions link; do not retain credentials indefinitely to retry. A late callback/worker must not resurrect a deleted connection. Deselection removes cached events for that calendar and cancels its work. Account deletion cascades local provider data. Other Farash users never inherit access merely because the Google calendar is shared.

## Event and refresh semantics

Provider dates and instants remain canonical. Jalali and Persian-digit conversion is display-only. All-day start/end stay date-only with exclusive end; never convert them through UTC midnight. Timed blocks preserve offsets and IANA zones; rendering follows the user's selected display zone. Recurring instances retain their original-start identity even when moved. Cancelled exceptions suppress only that instance; cancelled masters invalidate all their rendered windows. Permission-restricted/missing titles display a generic busy label; fetch no attendees, conferencing, attachments or descriptions in this first overlay. Provider recurrence is not recalculated with Farash's task recurrence engine. [Events] [Recurring]

Use two separate caches:

1. **Change detection:** per-calendar unexpanded masters/exceptions with `singleEvents=false`, deletion handling and consistent parameters. Consume all pages and publish the next sync token only after the complete transaction/checkpoint; an empty page does not imply completion. Google forbids time-window filters with a sync token. On token expiry (410), invalidate that calendar's event store/cursor and rebuild; do not clear unrelated task data. [Sync] [List]
2. **Rendered windows:** fetch provider-expanded `singleEvents=true` results for a bounded view range, independent of the change cursor. Initial window is today minus 30 through plus 60 days; each requested range is at most 93 days. A complete fresh window replaces its prior generation atomically. Change detection invalidates affected windows; changing a master invalidates all retained windows for that calendar. Do not expand infinite recurring masters locally. [List]

Farash bounds: at most 5 connections/account, 20 selected calendars/connection, 500 results/page, 20 provider pages/job, 100,000 stored resource rows/connection and 10,000 instances/window. Jobs checkpoint safely and yield after 30 seconds. A cap produces an explicit incomplete/limit state; no new sync cursor or partial complete-window flag. Retain at most 8 windows/calendar for 7 days. Poll active selected calendars no more often than every 5 minutes; manual refresh is coalesced and limited to once/minute/connection. These are initial product limits, not Google quota claims.

One refresh lease per calendar/generation prevents overlapping jobs. Retry transient errors and quota/rate-limit reasons with bounded exponential backoff and jitter, respecting retry hints. Do not retry permanent validation errors blindly. Attempt one credential refresh after invalid access credentials; revoked/invalid refresh authorization becomes `reconnect_required`, stops jobs and hides event details. Provider permission loss removes that calendar's cached data. Old completed data during network failure is explicitly marked stale, never presented as newly refreshed. [Errors]

## UX and implementation gates

Connections live in settings; selected calendars and freshness appear in the calendar view. Use the same ColorScheme, typography and controls as the current design. Show pending, connected, refreshing, stale, reconnect-required, limited and disconnected states. External events are visibly read-only and distinct from task completion controls. Preserve safe areas, 48dp targets, RTL, large text and keyboard navigation. No enabled-looking connect button ships before authorization works.

Implement as focused slices, each remaining open until its gates pass:

1. Configuration validation, provider interface, encrypted credential store, authorization state machine and disconnect fencing; fake-provider tests plus Google sandbox consent/callback proof.
2. Calendar selection, paginated resource/window fetching, incremental invalidation and worker limits; test interrupted pages, empty pages, 410 recovery, changed ACLs, duplicates, deletion and late-worker races.
3. Web/Android connection UX and read-only overlay; test browser denial/replay, Android handoff/process death, expired login, DST gap/fold, cross-zone midnight, multi-day all-day events, moved/cancelled instances and dense calendar limits.

Before enabling production: real provider consent and revocation smoke test, no-token-in-log/export assertion, foreign-owner 404 tests, actual Android signed-build handoff test, narrow/light/dark/large-text captures, required Go/Flutter/Web/Android CI. No real account write, store publication or two-way sync is implied by these tests.

## Official references

Checked 2026-10-23. Provider facts above link to these sources; limits, routes and storage are Farash design decisions.

[OAuth]: https://developers.google.com/identity/protocols/oauth2/web-server
[Scopes]: https://developers.google.com/workspace/calendar/api/auth
[List]: https://developers.google.com/workspace/calendar/api/v3/reference/events/list
[Events]: https://developers.google.com/workspace/calendar/api/v3/reference/events
[Recurring]: https://developers.google.com/workspace/calendar/api/guides/recurringevents
[Sync]: https://developers.google.com/workspace/calendar/api/guides/sync
[Errors]: https://developers.google.com/workspace/calendar/api/guides/errors
