# Stored recurring occurrences (#10)

The pure recurrence engine remains authoritative for calendar, selectors, DST,
late completion, count and end rules (see recurrence-engine.md). A rule anchors
to the task's current due date and explicit IANA timezone. Moving the due later
does not silently replace that anchor. Editing a rule preserves its emitted
counter; removing then adding starts a new series.

Each completed occurrence remains an ordinary completed task, retaining its
own time entries, rewards and Scrum history. The same database transaction
creates one fresh open successor, copies title/description/priority/section,
labels, deadline and duration, and stores the original schedule plus incremented
issued count. Retry close of the old task never produces a duplicate successor.
No missed-slot backlog is generated. A successor starts outside Scrum scope.
Description checkboxes are copied literally; no automatic reset is claimed.

GET/PUT /api/v1/tasks/{id}/recurrence read/set/remove the schedule. PUT accepts
{schedule: <engine schedule>} or {schedule:null}. Ordinary close advances it.
POST .../recurrence/skip hides that occurrence using soft deletion, creates its
successor and records skip without completion credit. Skip retries are safe.
POST .../recurrence/undo restores a skipped/completed occurrence and removes its
untouched successor. Ordinary reopen also undoes completion advancement.

Undo conflicts (409 recurrence_state_conflict) if the successor has been edited,
completed, deleted, given children, time records or Scrum metadata. Task comment
creation, editing and deletion also invalidate the successor version guard; deleting
a comment does not make the successor safe to discard again. An idempotent create retry
does not add a new task version; edit and delete requests conservatively update it. It never discards later
work. Completion/skip/undo events are append-only owner-scoped audit rows.
All task/schedule routes answer 404 for another account's object. Account/task
deletion cascades recurrence data. Migration 012 is additive; rollback may leave
these tables in place but must not drop history.

Initial activation is intentionally limited to standalone leaf tasks. Attaching
a rule to a subtask/parent is rejected; adding children later blocks advancement
rather than guessing reset semantics. Nested recurrence semantics remain a
follow-up under #10. Sharing and offline retry queues remain separate delivery
lanes. Local execution was unavailable during source preparation; CI must pass
PostgreSQL integration, formatting/static analysis and client checks before merge.

## Client editor and remaining scope

Task details expose the recurrence editor for eligible tasks with a due date.
It supports Gregorian/Jalali rules, due/completion basis, interval, weekly and
monthly selectors, total count and an optional end date through the shared date
picker. New rules use the task's existing due date as the anchor; the editor does
not provide a separate start-date control. Editing an existing occurrence retains
the original series anchor, wall time, timezone and emitted count. Changing the
count edits the total series limit, rather than restarting its allowance.

A new timed rule requires the task's stored timezone to match the device timezone
when deriving its wall time. Existing schedules preserve their stored wall time.
The server still validates selector/anchor compatibility and returns conflicts for
unsafe undo. These controls do not complete all of #10: nested-task recurrence,
shared semantics and durable offline retry queues remain follow-up work.
