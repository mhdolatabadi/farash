---
name: Farash
description: Night glass: a calm indigo room lit by two lights, with frosted glass only where the list passes beneath.
colors:
  primary: "#E8B66B"
  on-primary: "#21170A"
  accent: "#A9C4B2"
  overdue: "#EF8C8F"
  surface: "#161B33"
  ink: "#F1EEF6"
  muted-ink: "#B4B6C8"
  selected: "#2B3466"
  on-selected: "#F1EEF6"
  backdrop-1: "#141A3D"
  backdrop-2: "#0D1129"
  backdrop-3: "#090C1D"
  lamp: "rgba(240, 184, 104, 0.30)"
  room-light: "rgba(74, 88, 216, 0.50)"
  pane: "rgba(255, 255, 255, 0.12)"
  pane-border: "rgba(255, 255, 255, 0.16)"
  edge: "rgba(255, 255, 255, 0.14)"
  shadow: "rgba(0, 0, 0, 0.40)"
  priority-1: "#F08A84"
  priority-2: "#F2A65A"
  priority-3: "#8DB1F2"
  priority-4: "#9096AE"
  day-primary: "#8A5A12"
  day-on-primary: "#FFFFFF"
  day-accent: "#3F6B52"
  day-overdue: "#B3343F"
  day-surface: "#F8F7FB"
  day-ink: "#1B1E2C"
  day-muted-ink: "#545A6D"
  day-selected: "#E4E6F4"
  day-on-selected: "#1B1E2C"
  day-backdrop-1: "#E8EBF6"
  day-backdrop-2: "#F3F2F4"
  day-backdrop-3: "#F1E9DD"
  day-lamp: "rgba(242, 194, 122, 0.55)"
  day-room-light: "rgba(142, 162, 242, 0.45)"
  day-pane: "rgba(255, 255, 255, 0.60)"
  day-pane-border: "rgba(255, 255, 255, 0.90)"
  day-edge: "rgba(255, 255, 255, 0.70)"
  day-shadow: "rgba(27, 30, 44, 0.10)"
  day-priority-1: "#C0392F"
  day-priority-2: "#B3600B"
  day-priority-3: "#2F5FC4"
  day-priority-4: "#7A7F90"
typography:
  heading:
    fontFamily: "Noto Naskh Arabic (FarashNaskh), Vazirmatn"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.35
  title:
    fontFamily: "Vazirmatn"
    fontSize: "22px"
    fontWeight: 700
  body:
    fontFamily: "Vazirmatn"
    fontSize: "16px"
  metadata:
    fontFamily: "Vazirmatn"
    fontSize: "12px"
  action:
    fontFamily: "Vazirmatn"
    fontSize: "14px"
    fontWeight: 700
rounded:
  control: "12px"
  card: "16px"
  capture: "20px"
  pane: "24px"
spacing:
  compact: "8px"
  pane-inset: "12px"
  standard: "16px"
  sheet: "24px"
components:
  button-primary:
    backgroundColor: "{colors.primary}"
    textColor: "{colors.on-primary}"
    rounded: "{rounded.control}"
    height: "48px"
  button-text:
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    height: "48px"
  capture-bar:
    backgroundColor: "{colors.pane}"
    rounded: "{rounded.capture}"
    height: "56px"
  app-bar:
    height: "64px"
  navigation-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.on-selected}"
    rounded: "{rounded.control}"
  glass-pane:
    backgroundColor: "{colors.pane}"
    rounded: "{rounded.pane}"
  done-stamp:
    textColor: "{colors.primary}"
    rounded: "6px"
---

# Design System: Farash

## Overview

**Creative North Star: «شیشهٔ شب» (night glass)**

Farash is a quiet indigo room at night, lit by two lights: a warm lamp that moves to a new spot for each project, and a cool light across the room. The task list sits directly in that room. Frosted glass appears only where content actually passes beneath it: the app bar once the list scrolls under, the capture bar floating over the end of the list, the navigation pane and the editor side sheet. The blur always has light behind it, so the glass reads as glass.

The structure is plain Material 3, so a Todoist or TickTick user trusts it at once:
- a medium top app bar that names the project and collapses as the list scrolls
- a drawer on phones and a navigation pane on wide screens
- a modal bottom sheet for the editor on phones and a full-height side sheet beside the list on wide screens

The brand lives in the light, the Naskh project title and the done stamp, not in invented controls. Issue #49 replaced the #47 patterned-glass look after an impeccable critique. That critique found nested panes, a title-less phone bar, a floating editor card, and blur with nothing to frost.

Night is the designed default; day is the same room by daylight.

**Key Characteristics:**
- Two lights behind the glass: a moving honey lamp and a fixed cool room light.
- Glass only over passing content, one pane per region, never glass on glass.
- A medium top app bar with the project in Naskh; the toolbar title appears only as the large one fades.
- Full-bleed rows on phones; a 760px measure on wide screens, with the bar's glass spanning the column.
- Honey means now; sage means tomorrow; pomegranate means overdue.

## Colors

Every color comes from `FarashPalette.nightGlass` in `lib/app/palette.dart`. The palette feeds the Material theme, the backdrop, the glass and the priority marks.

- **Neutrals** (sheets, menus, dialogs, fields) are generated from an indigo seed (`#3A4A9A`), so every solid surface belongs to the same night instead of a warm brown.
- **Honey** (`primary`) is spent on "now":
  - today's dates
  - the «انجام شد» stamp
  - the focused capture edge
  - the single primary action of a view (save, send)
- **Sage** (`tertiary`) marks tomorrow.
- **Pomegranate** (`error`) marks overdue and destructive actions.
- **Priorities** keep the familiar red, orange, blue and grey order, tuned per brightness. They come from `priorities` in the palette through `TaskPriority.colorIn(context)`, never from a fixed hex. A filled check takes a dark tick on light tones.

Tests hold contrast in both themes:
- every text role at 4.5:1 or better on glass composited over each backdrop stop, and on the sheet and menu surfaces
- priority marks at 3:1 or better

**The One Lamp Rule.** If honey appears on something that is neither "now" nor the primary action, it is a bug.

## Typography

**Headings.** The project's large title and the app name use the headline roles. These are set in Noto Naskh Arabic Bold, bundled as `FarashNaskh` (OFL), with Vazirmatn as fallback and a 1.35 line height. Everything else is Vazirmatn through the Material 3 roles:
- **Collapsed bar title:** titleLarge, bold.
- **Editor title:** headlineSmall size in Vazirmatn, because editable text stays in the reading face.
- **Task titles:** bodyLarge, up to three lines.
- **Previews:** bodySmall.
- **Metadata:** labelMedium.

Text keeps its configured scale. The bar's expanded height grows with the text scale, up to 2×.

**The Persian Reading Rule.** Keep RTL and directional spacing everywhere, including the drawer's exposed edge, and isolate the account email as LTR.

## Layout

**Navigation.**
- **Phones:** the scaffold has no app bar of its own. The list carries the project's medium top app bar, with the drawer button and the show-completed toggle.
- **Wide screens:** at a viewport width of (840px) and above, a (288px) glass navigation pane sits inset (12px) from the edges. The list fills the rest directly over the room.

**Task list.**
- Task content keeps a (760px) measure. The app bar's glass and the scroll area span the whole column, so rows pass under the bar.
- The capture bar floats over the end of the list: (12px) from the edges, constrained to the same measure, above the safe area. The list measures it and leaves room to scroll the last task clear of it.
- When available height is below (240px), as with a landscape keyboard, capture moves above the tasks in the shared scroll view. The app bar becomes a single non-pinned row there. A GlobalKey keeps the draft across the move.

**Editing.**
- At a project-pane width of (820px) and above, the editor is a standard side sheet: full height, (400px) wide, at the end edge beside the list.
- Narrower screens open a modal bottom sheet. The sheet's action row stays in reach above the keyboard and the safe area.

**The Reachable Control Rule.** Every action target is at least (48px): completion, icon actions, the bar's actions and primary buttons.

## Elevation & Depth

**The room.** `GlassBackdrop` paints a vertical night gradient with two radial blooms:
- **Cool room light:** fixed toward the bottom start.
- **Honey lamp:** moves to a stable spot for each project over 900ms (easeInOutCubic) and holds still under reduced motion.

**The glass.** `GlassSurface` is a frosted pane:
- blur at sigma 20
- a 12% white tint at night (60% by day)
- a 1px light border
- a lit top edge
- an optional soft shadow (0 8px, blur 24px) for floating panes

The app bar uses the same tint and blur as a flat band with a bottom hairline, and only fades in once content scrolls beneath it.

Solid surfaces (drawer, bottom sheets, dialogs, menus) sit over a scrim and use the indigo `surfaceContainer` roles.

**Motion.**
- Small state changes take 160ms, and rows and pages take 280ms.
- A completed row lingers for 220ms, stamped «انجام شد» (a 160ms easeOutBack press), before it folds away.
- Entry eases out and exit eases in.
- The bar's glass fades in over 160ms.
- All authored durations become zero under reduced motion.

**The Single Pane Rule.** One pane of glass per region. A pane never contains another pane, a field box, or a card.

## Shapes

- **Radii:** controls 12px, cards and menus 16px, the capture bar 20px, and large panes, sheets and dialogs 24px.
- **Selection:** selected and picked task rows round to 12px.
- **Drawers:** curve their exposed end edge.
- **Completion check:** a circular visible check sits within a 48px target.
- **Hairlines:** task hairlines start at the title edge.

## Components

**Top app bar.**
- Its leading drawer button appears only where a drawer exists.
- The large title row holds the project mark (the Inbox icon or the project's color dot), the Naskh name and the open count, plus planned time when there is any.
- The toolbar title shows only after the large title fades, so there is exactly one title at a time, for both sight and semantics.
- The show-completed toggle is an icon button with a selected state.

**Capture bar.**
- One glass pane holding the text field, the priority menu and the filled send button.
- It is edged in honey while focused.
- Send grows from a muted state once there is text.

**Task rows.**
- Rows are flat. Each shows the title, a description preview, checklist and subtask counts, and dates.
- Pointer drag handles appear on hover; touch keeps a quiet handle at the row end.

**Editor.**
- The first row holds the title (hint «عنوان کار») and the close button, followed by the notes and a divider.
- Next come the property rows: schedule, segmented priority, project and section.
- Checklist and subtasks open on demand.
- A fixed action row closes the editor, with delete as an icon apart at the start and the primary save at the end.

**Navigation pane.** It combines the project mark, the title, tonal selection and hover-revealed row menus, with the app name above the account email.

## Do's and Don'ts

### Do:
- Do take every color from `FarashPalette.nightGlass`, priorities included.
- Do use glass only where content passes beneath it, and keep light behind it.
- Do name the current project in the app bar on every width.
- Do open editing as a side sheet beside the list on wide screens and as a modal bottom sheet on phones.
- Do keep honey for "now" and the primary action.
- Do stamp completions before folding them.
- Do honor reduced motion: the lamp, rows and bar hold still.

### Don't:
- Don't nest glass in glass, or put a boxed field or card inside a pane.
- Don't frame the whole phone screen in a pane.
- Don't float the editor as a short card inside the list.
- Don't add texture patterns to the glass. The #47 pebble relief read as noise.
- Don't add eyebrow labels above titles or tiny floating labels over the editor title.
- Don't spend honey on secondary buttons, icons or selection.
- Don't introduce controls for unimplemented features.
- Don't claim hardware or accessibility-service validation from source inspection.
