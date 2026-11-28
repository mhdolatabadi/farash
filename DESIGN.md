---
name: Menval compact workspace
description: Approved Persian-first tactile task, habit and calendar workspace.
---

# Menval design system

The owner's November 2026 reference and subsequently approved interactive desktop
workspace are the visual authority. This replaces the older teal Material/bento
brief. The interface is an Operate surface: real planning data, fast capture,
readable content and consistent controls. No decorative illustrations, invented
statistics or additional dashboard cards.

## Shared controls

`lib/app/design_tokens.dart`, `controls.dart`, `palette.dart`, `soft.dart` and
`app_theme.dart` own geometry, states and color. Controls have a minimum 48px hit
area, 12px corners and 20px icons. Checkboxes share one 20px circular mark with a
14px check inside the 48px target, including task, subtask, checklist and habit
uses. Numeric and skipped habit states retain their meaning.

Raised controls sit above inset content wells. Press feedback sinks the surface;
keyboard focus has a visible 2px outline. Transitions take 120ms and respect reduced
motion. Disabled controls cannot act. Labels/tooltips describe icon-only actions.
Text uses bundled Vazirmatn, Persian-first RTL, and wraps or truncates safely.

## Palette

Current light: ground `#F1EDE9`, surface `#F2EEEB`, well `#EAE5E0`, ink
`#34332F`, muted `#706D66`, primary `#5A564E`, light `#FFFDFA`, shade `#D2CCC6`.
Current dark: ground `#272724`, surface `#2D2D29`, well `#242520`, ink
`#EEECE5`, muted `#B4B1A8`, primary `#DDD8CB`, light `#3B3C35`, shade `#191A17`.
Errors and task priorities retain distinct accessible semantic colors.

Gray/gold, burgundy/gold and navy/neon-green are future palette proposals. Their
reserved tokens do not add an appearance setting or alter the current palette.

## Desktop composition

A right sidebar keeps the Menval wordmark, destinations, projects and account
reachable. Search sits at the top left; appearance is beside it. The rail is 208px
(or 176px on the smaller desktop), main content has generous side gutters and a
1160px maximum width. Content never stretches to the viewport edges.

Task lists use compact rows with the title, completion mark and time visible in
one scan. Simple rows are 52px; large text and meaningful metadata may grow them.
An opened task occupies a 288px contextual pane to the left of the list when space
allows. Switching tasks or destinations protects unsaved edits. Creating a task
refreshes data without remounting the editor or discarding its draft.

## Capture and navigation

The plus is icon-only and contextual: task list creates a task, habits creates a
habit, calendar creates an independent calendar event. Capture opens inside the
page, retaining the surrounding list/grid. Task capture needs only a title;
date/time is optional. Failure preserves input, repeated submissions are guarded,
and uncertain recurring-task/habit/event creates reuse their original intent.
Task notes are not shown or edited; existing stored descriptions/checklists are
preserved. The workspace `q` shortcut opens task capture without stealing typing
or acting behind another route. Ctrl/Cmd+K opens search.

Phones retain the compact three-tab navigation with inset active tab, brand top
right, search top left, safe areas and bottom padding clearing the floating action.
Keyboard and large-text layouts must keep capture and remaining content usable.

## Habits and calendar

Habit rows are compact 52px rows with names kept visible while history scrolls.
Ranges are 7, 14 or 30 actual local calendar days ending today. Switching ranges never
changes the date of a stored check-in. Boolean four-state and numeric habits,
reordering, filters and detail editing remain available.

The week has seven equal day columns, Saturday-first in Persian settings, and
shared time labels. Scheduled tasks and independent native events share overlap
lanes. Event capture/editing remains inline and retains the selected week.
Provider calendars remain read-only; native events have their own owner-scoped
persistent model. See `docs/native-calendar-events.md` for exact data behavior.

## Validation

Behavior tests cover creation/retry, draft protection, range date identity and
shared control semantics. Capture the actual Flutter app at 1440, 1024 and 320px,
light and dark, including keyboard/large-text conditions. Keep native Android
screenshot coverage, release web compilation and Android build gates. Mockups
alone do not constitute acceptance of the implementation.
