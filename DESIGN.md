---
name: Farash Calm
description: A calm Material 3 task app on a soft ground; one accent, raised tiles, dense lists in wells, no ornament.
colors:
  day-primary: '#0E7490'
  day-on-primary: '#FFFFFF'
  day-primary-container: '#D9EEF2'
  day-on-primary-container: '#0B4F63'
  day-accent: '#0757B5'
  day-surface: '#FFFFFF'
  day-ink: '#1B1F24'
  day-muted-ink: '#5F6670'
  day-container-low: '#F6F7F9'
  day-container: '#F0F2F4'
  day-outline: '#C9CED4'
  day-divider: '#EEF0F2'
  day-error: '#B42318'
  day-soft-ground: '#E9EDF1'
  day-soft-light: '#FFFFFF'
  day-soft-shade: '#C9D0D7'
  primary: '#C8F25A'
  on-primary: '#0F1115'
  primary-container: '#2E3A14'
  on-primary-container: '#DDF79A'
  accent: '#74A7FF'
  surface: '#0F1115'
  ink: '#ECEDEE'
  muted-ink: '#9BA1A6'
  container-low: '#15181D'
  container: '#191C22'
  outline: '#4A4F57'
  divider: '#1E2127'
  error: '#FF8A8A'
  soft-ground: '#16191E'
  soft-light: '#22262D'
  soft-shade: '#0A0C0F'
typography:
  title: {fontFamily: Vazirmatn, fontSize: 22, fontWeight: 700}
  body: {fontFamily: Vazirmatn, fontSize: 16}
  timer: {fontFamily: Vazirmatn, fontWeight: 700, features: tabular}
rounded: {field: 12, surface: 16, tile: 22, sheet: 28, button: stadium}
spacing: {xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32, gutter: 16, keyline: 56}
---

# Design System: Farash Calm

## Overview

Farash is an Operate surface: people open it to capture and finish work, so a category-fluent user should trust every screen immediately. Material 3 governs structure, navigation and components; the brand lives only in color, Persian typography and precise spacing. There is no illustration, metaphor, reward art or ornament. The owner chose this after rejecting the glass, garden and weaving looks; the comparison board is at https://claude.ai/artifact/DtsjUw4u7MrgYgF15jpevY (row A for structure and the light theme, row C for the dark colors). In October 2026 the owner added a soft bento layer to the three main destinations, blending three Dribbble directions: bento tiles, soft UI and dense Linear-style rows (issue #146; options at https://claude.ai/artifact/XwCrpTtJBADVWoYgHUvzYv).

## Colors

One accent per theme. By day: white surfaces, ink text, teal `#0E7490` for the primary action, today, the running timer and selection. By night: near-black `#0F1115`, light ink, and lime `#C8F25A` with dark text on it. Tomorrow uses the blue accent; overdue dates and errors use the error role, and nothing else does. Priorities keep the familiar red, orange, blue and grey per theme (`FarashPalette.calm`). Every color reaches widgets through `ColorScheme` roles or `FarashPaletteColors`; widgets never hard-code hex values.

## Typography

Vazirmatn for every role, Persian digits, RTL first. Screen titles use `titleLarge` bold; section labels in lists use `titleSmall` bold in muted ink; task titles use `bodyLarge`. The timer uses tabular figures, isolated LTR, scaled to the ring. Text follows the user's scale; at large scales, controls wrap rather than truncate.

## Layout

Phones: four destinations in the navigation bar, امروز, کارها, تمرکز and, with time support, زمان‌ها (habits add عادت‌ها). The drawer holds views, projects and labels. At 840 logical pixels and wider, a sidebar replaces the bar; it lists the Inbox and views first, then the tools (تمرکز, زمان‌ها, عادت‌ها), then projects and labels, so nothing appears twice. Lists keep a readable measure on wide screens.

The sidebar and drawer (issue #158) follow the common shape of task-app sidebars on Dribbble: brand on top, a search field sunk in as a small well, then compact rows in labelled groups, with the progress and the account pinned under a hairline at the bottom. On wide screens the sidebar lies on the same soft ground as the page, set off by one hairline. Rows share one style (`SidebarTheme`): 18 icons, medium-weight titles, 36 high under a pointer and 48 on touch, and a muted open-task count at the row's end that turns into the row's menu on hover (`HoverSwap`). Groups: Inbox and the views (no label), «ابزارها» (تمرکز, زمان‌ها, عادت‌ها, wide screens only), favourites, «پروژه‌ها» with quiet archive and add buttons, and «برچسب‌ها». Only the open row changes: it stands up as a raised pill with the accent on its icon and title. «پیشرفت من» is one flat line with the level, a thin bar of this week's days and a caption; under it the account row (initial, email, menu) holds the account's actions. Capture is not a navigation row: the capture bar on each list and the `q` shortcut cover it.

Spacing comes from one 4-point scale in `lib/app/spacing.dart` (`Space`), never from one-off numbers. Every list lines up on two keylines, measured from the edge of the well it sits in (the well itself starts 14 in from the screen edge): the 16 gutter, where check circles, section labels, the empty-list line and header icon glyphs start, and the 56 content keyline, where row titles, row dividers and the header's mark (beside the menu) start. List rows run edge to edge and carry the gutter themselves; containers do not add their own side padding. The header's open count shares the title's start edge and sits just under it. A section label takes 24 above and 4 below, so it belongs to the rows it names; the first one under the header takes 8. In the task editor, actions such as «افزودن زیرکار» are rows with the same icon and label keylines as the properties above them, not loose text buttons. The capture field stays above the navigation and safe areas, and the last task always scrolls clear of it.

A saved `garden` or `weaving` start view migrates to `today`, which is also the default.

## Elevation and shapes

Every screen, sheet, dialog and menu stands on `softGround`, which is also the theme's `surface` (`lib/app/soft.dart`); the owner asked for the soft layer on every page and detail screen (issue #155). A summary sits on a `SoftTile`, which rises off the ground with a shade shadow toward the bottom end and a light shadow toward the top start. A list or the focus dial sits in a `SoftWell`, sunk in with inner shadows. Tiles and wells use a 22 radius, and both carry a hairline, so an edge never depends on a shadow alone. Slivers that cannot paint inner shadows use the flat `Soft.wellDecoration`. `Panel` is a raised tile too, so the side editor, the sign-in card, the sprint card and the time totals rise off the ground. Every list of rows (projects, upcoming, 7 days, all, search, the sprint backlog and board columns, time entries, badges, the task editor's properties and subtasks) sits in a well, with dense rows. Habit detail sections, the weekly report and challenge, and the level and points on «پیشرفت من» are tiles. Fields are small wells: filled a touch darker than the ground, with a hairline. Nothing is flat white any more; tone and the two shadows separate layers. Tiles and wells never nest more than one level deep. Buttons are stadium-shaped and at least 48 high; fields have a 12 radius outline; sheets and dialogs use 28. The FAB keeps Material's small elevation.

## Components

- **Task rows** are full-width and flat, separated by a hairline that starts at the title. The check circle takes the priority color. Selection fills the row with the primary container. Near dates sit in a tinted pill: today in the primary, tomorrow in the accent, late in the error color.
- **امروز bento**: a date tile with the day numeral in the primary color, a tasks tile, a focus tile with the live timer and a play button, and a habits tile with up to five check squares. The tasks tile shows «۳ از ۴» with a ring only when the progress API confirmed today's done count; otherwise it shows only the open count. At text scale 1.5 and above, the tiles stack. Below the tiles, the day's rows are dense (6 vertical padding, the check keeps its 48 target) and sit in one well.
- **عادت‌ها** opens with two tiles, today's done count with a ring and the best current streak, and puts the Loop-style grid in a well.
- **Navigation** uses Material's indicator in the primary container, labels bold when selected.
- **Focus** has a segmented mode picker (chips when the labels do not fit), one progress ring around the timer that shows real elapsed time, set in a round well, the task title under it, and a large primary start/pause button with a small soft-tile reset beside it. Its lifecycle and time-tracking behavior are described in `docs/time-tracking.md`.
- **Sidebar progress** (level, XP, weekly goal) comes from the account API; unavailable data never shows an invented score.

## Motion

150 to 280 ms, conveying state only: row arrival and completion, the check, page fades. `Motion.of` removes durations when reduced motion is requested.

## Do's and Don'ts

- Do keep one accent per theme and use it only for primary actions, today, the running timer and selection.
- Do follow Material 3 components before inventing a control.
- Don't add illustrations, metaphors, decorative glow, glass or gradients. Outside the soft layer, don't wrap lists in cards.
- Don't show progress, rewards or scores the server did not confirm.
