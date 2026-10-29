# Google Calendar broker: initial runtime slice

Refs #119. The backend now implements the authorization broker and on-demand,
read-only calendar/event API. This is a first slice, **not** background incremental
synchronization or a completed production OAuth rollout. Calendar events do not
become tasks and provider writes are never requested.

## Configuration

Disabled by default. When `CALENDAR_GOOGLE_ENABLED=true`, startup validates all
configuration and fails without printing values if incomplete:

- `CALENDAR_GOOGLE_CLIENT_ID`, `CALENDAR_GOOGLE_CLIENT_SECRET`: confidential Google
  web application client; keep the secret outside source control.
- `CALENDAR_GOOGLE_CALLBACK_URL`: exact registered HTTPS URL ending
  `/api/v1/calendar-connections/google/callback`.
- `CALENDAR_WEB_RETURN_URL`, `CALENDAR_ANDROID_RETURN_URL`: fixed HTTPS destinations,
  without credentials, query strings or fragments. No client-supplied redirect is
  accepted. Android initially resumes or manually refreshes the settings screen;
  a verified signed-build App Link return remains a release gate.
- `CALENDAR_TOKEN_KEY_ID`: active key identifier (letters, digits, underscore, dash).
- `CALENDAR_TOKEN_KEYS`: JSON key ring mapping key IDs to base64-encoded 32-byte
  keys. Generate keys outside source control, for example with
  `openssl rand -base64 32`. Never paste the output into an issue or application log.

Keep old key IDs available during rotation: old credentials remain decryptable,
while refreshed credentials use the active key. Back up the key ring separately
from PostgreSQL and keep its access limited; a database backup alone cannot restore
calendar access. Removing an old key too soon requires reconnecting those accounts.
Compose passes these optional variables to the API. No secret or OAuth registration
is provisioned by this change. The API logs no authorization URLs, codes, state,
credentials or event content. If access logging is enabled at any proxy in front of
it, redact query strings for the broker start and callback routes.

## API

All JSON routes require the Farash bearer token and return `Cache-Control: no-store`.
Only the browser ticket entry and Google callback are public.

| Route | Response / behavior |
| --- | --- |
| `GET /api/v1/calendar-connections` | `{configured, connections:[{id,provider,status,version}]}`; explicit configured=false when disabled. |
| `POST /api/v1/calendar-connections/google/authorize` | `{client:"web"\|"android",consent?:boolean}` → `{start_url}`. Open the returned URL in the system browser. |
| `GET /api/v1/calendar-authorize/start?ticket=` | Single-use 256-bit broker ticket, Secure/HttpOnly/SameSite=Lax correlation cookie, redirect to Google with S256 PKCE and state. |
| `GET /api/v1/calendar-connections/google/callback` | Consume matching state+cookie once; exchange code server-side, then fixed HTTPS return with no tokens or code in the destination. |
| `GET /api/v1/calendar-connections/{id}/calendars` | `{calendars:[{id,title,time_zone,selected}],version}` after a complete provider calendar-list read. |
| `PUT /api/v1/calendar-connections/{id}/selection` | `{calendar_ids:[opaque IDs],version}` → `{version}`. |
| `GET /api/v1/calendar-connections/{id}/events?from=&to=` | RFC3339 instants, window ≤93 days → `{events,complete:true}` only after every requested page completes. |
| `DELETE /api/v1/calendar-connections/{id}` | `{disconnected:true,revoked:boolean}`; local erasure/fencing succeeds even if remote revocation fails. |

Connection IDs and calendar IDs are opaque local IDs; raw provider calendar IDs,
access/refresh tokens, PKCE verifiers and state hashes never enter JSON responses or
account exports. Missing or foreign connections answer 404 before contacting Google.
Event IDs are stable hashes scoped to the local connection and calendar. Events
contain title, date/dateTime/timeZone start/end, status, calendar_id and read_only=true.
No descriptions, attendees, attachments, conferencing or private links are fetched.
All-day end dates remain exclusive; no UTC-midnight conversion is performed.
Google expands recurring instances for the requested window; cancelled entries are
excluded. Farash does not reinterpret provider recurrence with task rules.

## Bounds and failure behavior

One Google connection/account in this slice. Authorization attempts expire after
10 minutes, are capped at three pending attempts/account and consume ticket/state
atomically. The browser ticket establishes the correlation cookie without putting a
Farash bearer token in a URL. Concurrent callbacks/disconnects are fenced by an owner
epoch; a consumed but late successful callback cannot recreate a disconnected account.

Selection is capped at 20 calendars. Calendar discovery caps at 500 calendars/20
pages. A window fetch caps at 20 provider pages total and 10,000 events; no partial
result is presented as a complete window. Requests have a 25-second overall deadline,
provider calls 20 seconds and provider responses a 2 MiB limit. Authenticated provider
operations are limited to ten/minute/account by the process-local limiter. Errors use
stable `invalid_calendar_input`, `calendar_state_conflict`, `calendar_limit_reached`,
`calendar_reconnect_required`, or `calendar_provider_unavailable` codes, never provider
response bodies or credentials.

Token refresh is serialized within the API process, preserves omitted refresh tokens,
and uses generation-checked writes; selection/disconnect fencing also protects late
reads. Credential ciphertext uses AES-256-GCM with a key ID and owner+connection-bound
associated data. Revoked refresh authorization sets reconnect_required. Explicit
re-consent is available through consent=true when offline credentials are missing;
it is not forced for every connection.

## Remaining gates / scope

- Run real Google sandbox consent, PKCE exchange, callback denial/replay and revocation
  tests with the selected registered web client before enabling production.
- Verify the exact signed Android browser/App Link return flow and Web same-browser
  correlation flow; unit/provider-fixture tests do not prove provider acceptance.
- Background refresh jobs, incremental sync tokens/410 recovery, completed stale
  window caches, provider backoff and multi-account connections remain future slices.
  Current requests read bounded live windows and do not persist event details.
- Outlook/CalDAV, two-way writes, calendar editing and invitations are not implemented.

Tests cover configuration and encryption binding/key rotation, fixed provider origins,
read scopes/PKCE, bounded responses, date-only preservation, pagination completeness,
refresh serialization, revoked status, owner isolation, ticket/state replay, expired
attempts, optimistic selection, and disconnect/late callback fences. Database cases
run in CI against PostgreSQL (`TEST_DATABASE_URL`); local runs without it skip them.

## Official provider references

Checked 2026-10-25:

- https://developers.google.com/identity/protocols/oauth2/web-server
- https://developers.google.com/workspace/calendar/api/auth
- https://developers.google.com/workspace/calendar/api/v3/reference/events/list
