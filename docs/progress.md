# Personal progress

`GET /api/v1/progress?timezone=Asia/Tehran` returns the authenticated user's
`completed`, `xp`, `level`, `level_xp`, `weekly_days`, `weekly_goal`,
`week_start`, and `badges`. The optional IANA timezone defaults to Tehran.
`PATCH` on the same URL accepts exactly `{"weekly_goal": 3}` (integer 1–7).
Invalid goals/time zones return 400; missing/expired authentication returns 401.
No caller-supplied owner ID is accepted. Backend failure returns 500 with
`progress_unavailable`; the client offers retry and never substitutes zeroes.

Rules:
- Every live completed task, including subtasks, contributes 10 XP. A parent
  completion that closes its subtasks credits each completed row once.
- Level starts at 1 and increases every 100 XP. Existing completed tasks count.
- The server derives progress from task state rather than incrementing counters.
  Duplicate close requests cannot add credit. Reopening and soft deletion remove
  credit; restoration restores it. Project/section deletion follows task state.
  Permanently deleting a project removes its tasks and their credit.
- A day is active after at least one currently completed task has its completion
  timestamp in that local day. Reopening/reclosing moves that task's credit to
  its latest completion day; it never produces two credits. This version is a
  current-state summary, not a permanent history of completion events.
- Weeks are Saturday 00:00 through the following Saturday (exclusive), calculated
  as calendar days in the requested zone, including daylight-saving transitions.
- Goal defaults to 3 active days and is saved per account across devices. Changes
  apply immediately to the current week. No missed-day penalties or streak loss.
- Milestone badges: 1, 10, 50, 100 completed tasks. The weekly badge represents
  the current week's goal. Badges are derived and reversible, not an award ledger.

Web and Android use the same navigation summary and scrollable details page.
Successful task/project/section mutations invalidate the summary; opening details
and resuming the app reload from the server. Multi-device changes are visible on
reload/resume. Progress never blocks task completion if its own request fails.

Migration 008 adds a constrained user goal and a partial completion index; no task
rewrite or external service is required. Deploy through the existing workflow.
For application rollback, leave the additive schema/index in place.

## Weekly report

The additive `week_report` field contains seven ordered `days` (Saturday first),
with local ISO date, completion count and `future` flag; zero-activity dates are
included. `completed` counts the current week through the response instant,
`previous_completed` counts the preceding Saturday through the same local
weekday/time last week. `compared_through` records the current cutoff.
Calendar-day arithmetic preserves the local comparison across DST transitions
(with Go's time normalization for nonexistent local times). This compares equal
local calendar periods, not a partial week against a whole previous week.
Future completions are excluded from weekly counts. Existing all-time XP rules
are unchanged. Counts are still derived from current task state; reopening or
deleting tasks can change a past day's count. They are not immutable history.
Older clients ignore the added field; newer clients hide the report when talking
to an older server. No schema migration is needed.

## Weekly personal challenge

`weekly_task_goal` is the per-account completed-task target, default 10 (1–500).
Authenticated `PATCH /api/v1/progress/challenge?timezone=Asia/Tehran` accepts
`{"target": 20}` and returns the updated full progress response. Invalid integers
return 400 (`invalid_challenge_target`); authentication and backend errors match
the existing progress endpoint. The active-day goal remains independent.
Changing a target applies immediately; completion is `week_report.completed >=
weekly_task_goal`. No extra XP or permanent award is issued. The target persists,
but progress resets with the existing Saturday/local week window. Reopening and
deleting tasks reverses progress. Clients hide the control with older servers.
Migration 009 adds the constrained goal column; keep this additive column when
rolling the application back.
