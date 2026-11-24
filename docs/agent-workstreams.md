# Menval coding agents: roles, authorization and WIP

This repository has four scoped Copilot cloud agent profiles under `.github/agents/`: `farash-ux`, `farash-offline`, `farash-android` and `farash-qa`. These Markdown files are **instructions**, not running processes or proof of agent authorization. Agents begin coding only after repository access is enabled and an authorized user starts a session/assigns a task to one. GitHub rejected Copilot issue assignment during the 2026-11-21 setup with HTTP 422/403, so do not claim autonomous execution until that is resolved.

To enable an agent, the repository owner should confirm that Copilot cloud agent is available to this repository and appears in the Issues > Assignees UI or repository Agents UI, then explicitly start/assign an issue. If access is unavailable, authorized Codex/other coding runners may follow the same file ownership and review rules; no user credential should be copied into issues.

| Workstream | Queue | File ownership | Dependency |
| --- | --- | --- | --- |
| UX Today | #169 | today_bento.dart, due_tasks_view.dart and tests | independent |
| UX editor | #170 | task_detail_sheet.dart, quick_add_dialog.dart, tests | independent of Today |
| UX focus | #171 | focus_view.dart, narrow home_screen.dart changes and tests | coordinate shared home_shell |
| Offline server | #172 then #21 | server Go, PostgreSQL migrations and tests first | client command queue waits for server contract |
| QA & release | #173, #120 | tests, CI tooling, release checks | checks every candidate PR |

Agents must keep one issue per PR, use branches and remain within file boundaries. Open PR does not mean finished. Verify format, analyze, Flutter tests, Go tests, Web build, Android build, emulator captures, and real-device release validation where relevant. Only reviewed and green changes are eligible to merge; deployment follows main. See #98 for status. Do not spend model tokens on repetitive "continue" replies: push one checkable unit of change per run and explain any blocker.
