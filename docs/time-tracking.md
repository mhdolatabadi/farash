# Task time tracking (#75)

Time entries are private, server-owned records, separate from estimates, completion counts and rug rewards. One interval can run per account. Starts carry retry keys; stopped-entry retries return the original interval and never start a second one. Stops name their expected entry, so a stale device cannot stop a later session. A reused key must match the original task and source; manual retries must also match both timestamps. A late successful retry for an already-ended interval returns that interval; the client asks for another explicit start instead of starting its local countdown.

Task-linked Focus starts recording automatically. Pausing/resetting closes the interval. Focus has a server-stored end deadline (maximum one hour at the API; the client offers 25-minute work sessions) so closing/suspending the client cannot record indefinitely. The local countdown is separate: it survives shell navigation but is disposed on app close and is not restored from history. Manually started work timers have no Focus deadline and continue across app close until stopped, corrected, deleted, or closed by task completion/deletion. Rest breaks and untargeted Focus do not create work entries. Completion or deletion closes active time for the task/subtasks in the same transaction. Undoing completion does not erase work already recorded.

An optional completion prompt offers 15/30/60-minute approximate entries or manual input when a task has no time entries. Dismissal records nothing. A persistent active-time strip allows inspection/stop across navigation, and polls every 30 seconds plus app resume. Elapsed display uses the server anchor plus a monotonic local clock. Mutations require a connection; failed writes are not represented as confirmed time. A returned authoritative active entry remains visible even if the following report refresh fails.

Manual entries may be created, corrected or deleted. Corrections preserve the original task and source and can close a stale running entry. Intervals must be positive, no longer than 24 hours and end no more than one minute in the future (clock-skew tolerance). Start/end use the existing Jalali-first calendar and device timezone; storage is UTC. Overlaps are permitted and summed, with an explicit editor note. No automatic claim of activity is inferred from a gap. Today’s gaps of at least five minutes, from local midnight through now, are optional backfill suggestions, hidden when the fetched history is truncated. Timers running over four hours receive a non-blocking correction/discard prompt.

Reports default to the current Saturday-based week in the requested IANA timezone; durations are clipped to query boundaries. Today is local midnight, including DST-aware boundaries. Arbitrary ranges are bounded to 32 days. A task-specific report defaults to lifetime total/recent entries after checking ownership; an explicit valid range overrides that default. Aggregates include every matching record; detail is limited to the latest 500 and marked truncated. Task totals and project groups retain their identities, so projects with the same name remain separate. Labels use current task/project titles, with a private task-title snapshot if a task is physically deleted.

API: GET/POST `/api/v1/time`; POST `/api/v1/time/{id}/stop`; PATCH/DELETE `/api/v1/time/{id}`. Another owner's task or entry returns 404. Schema migration `010_time_entries.sql` is additive. Normal deployment runs migrations before serving the updated API; rolling back the client/API can leave this table in place. Never drop activity history as rollback.

## Direction contract

THESIS: Capture actual work with minimal memory burden while keeping the task primary.
OWN-WORLD: Use the calm Material 3 surfaces in DESIGN.md, Persian type and quiet controls. No new dashboard or reward currency.
STORY: Pick a task, focus/record, see the active strip, then review/correct real time.
FIRST VIEWPORT: A short heading, today/week totals, task-start/manual actions. The active strip reserves layout space rather than covering content. Details/gaps follow in a scrollable column.
FORM: Ordinary extension of the user-pinned, code-led atelier system; preserve DESIGN.md and sidecar tokens.
FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

Evidence must distinguish synthetic UI fixtures, database integration tests, emulator captures and physical-device behavior. Hardware battery/background-service behavior is not a promised capability: timing is server timestamps, not a foreground service.
