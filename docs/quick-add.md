# Quick capture

Parsing runs on the device. The existing date, time, priority, `#project`,
`@label`, and `{deadline}` syntax now also recognizes `/section` and a bounded
recurrence grammar:

- `هر روز`, `هر ۲ هفته`, `هر ماه ۱ام`, `هر سال`
- `هر دوشنبه` (the next matching day, including today)
- `every day`, `every 3 weeks`, `every month on 31st`, `every monday`
- `every! 3 days` (relative to completion rather than the due date)

The preview chips can each be dismissed to keep their text in the title.
Selectors use the calendar setting at capture time, persisted in the structured
server recurrence rule along with the device IANA time zone. Monthly selectors
clamp to the last valid day of the selected calendar month. An explicit start
date that conflicts with a weekday/month-day selector is rejected before task
creation. The full recurrence editor remains available for rules beyond this
grammar.

Project selection resolves before section selection. Unknown or ambiguous
projects, missing or ambiguous sections, and sections in another project reject
the capture before creating a task. Dismissing the project/section chip keeps
it as literal title text instead. Labels retain existing create-if-missing
behavior.

Project capture and the global capture dialog share one capture session. Task
creation and schedule creation are two server requests. If task creation is
confirmed but the recurrence response fails, the original text is locked and
retry sends only the recurrence PUT for the confirmed task ID. It never repeats
confirmed task creation. Closing the capture leaves the ordinary created task;
its recurrence can be configured in task details. A lost response from the
initial task POST remains subject to the task API's existing behavior; this is
not a general offline queue or task-create idempotency implementation.

The signed-in shell exposes a named drawer action and the `q` shortcut. The
shortcut also works over normal pushed app pages, but ignores editable controls,
modified key combinations, modal routes, and an already-open capture dialog.
Capture targets the selected editable project in the project workspace and the
Inbox elsewhere. The shell refreshes after confirmed creation.

Integration with the Today inline capture introduced separately in #116 must
also use `QuickCaptureSession`; the separate direct-create path must not discard
parsed recurrence/section metadata. This change covers project capture and the
global dialog, not that separate inline path.

Regression coverage includes project/section scoping, recurrence retry with a
stable confirmed ID and account guards, parser selectors and dismissed tokens,
normal-page/modal/typing shortcut behavior, and a 320px dialog with 2× text and
keyboard insets in both themes. Flutter widget/build checks run in CI because
this workspace has no usable Flutter installation.
