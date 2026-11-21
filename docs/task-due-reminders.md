# Task due notifications (Android opt-in slice)

Task-due alarms are opt-in from the sidebar **اعلان سررسید کارها** row.
After Android notification permission is granted, the app schedules local
notifications at the due time of open tasks with an exact time. Date-only
tasks do not create alarms (they have no configured reminder time).
The notification opens the task's project; it does not change the task.

Only the next 14 days and the earliest 150 task alarms are scheduled.
They share the existing Android notification plugin with habit reminders;
each notification type is reconciled and cancelled independently.
A successful list response refreshes the plan at startup, app resume and
server-confirmed task changes. A failed/offline response keeps the previous
alarms rather than interpreting network failure as an empty task list.
Sign-out cancels pending task and habit alarms. Android may defer a reminder
when exact-alarm permission is unavailable.

Scope limitations for #14: this slice does not add early/relative reminders,
multiple alarms per task, daily digests, Web Push or notification action buttons.
Notification permission and settings should also be validated on a real Android
device before the release is considered store-ready.
