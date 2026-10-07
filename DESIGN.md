---
name: Farash
description: Dew on glass: peach, lavender and mint light behind white frosted glass by day, and the same hues low in a violet night.
colors:
  primary: "#B4A7FF"
  on-primary: "#1B1340"
  accent: "#8FD9BF"
  overdue: "#FF9AA6"
  surface: "#1C1834"
  ink: "#F1EEFA"
  muted-ink: "#B9B4CF"
  selected: "#332C66"
  on-selected: "#F1EEFA"
  backdrop-1: "#1C1736"
  backdrop-2: "#15122B"
  backdrop-3: "#0F0D20"
  lamp: "rgba(255, 158, 181, 0.22)"
  lavender-light: "rgba(150, 130, 255, 0.35)"
  mint-light: "rgba(110, 210, 180, 0.22)"
  pane: "rgba(255, 255, 255, 0.10)"
  pane-border: "rgba(255, 255, 255, 0.14)"
  edge: "rgba(255, 255, 255, 0.12)"
  shadow: "rgba(0, 0, 0, 0.35)"
  priority-1: "#FF8A9A"
  priority-2: "#FFB86B"
  priority-3: "#9FC2FF"
  priority-4: "#9A96B2"
  day-primary: "#5B45D6"
  day-on-primary: "#FFFFFF"
  day-accent: "#1F7A5C"
  day-overdue: "#B3263A"
  day-surface: "#FBFAFE"
  day-ink: "#1D1B2E"
  day-muted-ink: "#5D5A73"
  day-selected: "#ECE7FF"
  day-on-selected: "#1D1B2E"
  day-backdrop-1: "#F7F3FB"
  day-backdrop-2: "#F4F1F8"
  day-backdrop-3: "#F3F1F8"
  day-lamp: "#FFD9C2"
  day-lavender-light: "#D9D2FF"
  day-mint-light: "#C9F0E4"
  day-pane: "rgba(255, 255, 255, 0.62)"
  day-pane-border: "rgba(255, 255, 255, 0.95)"
  day-edge: "rgba(255, 255, 255, 0.80)"
  day-shadow: "rgba(80, 60, 140, 0.08)"
  day-priority-1: "#D23C4B"
  day-priority-2: "#C4670F"
  day-priority-3: "#3A63D0"
  day-priority-4: "#8B88A0"
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
  task-card:
    backgroundColor: "{colors.pane}"
    rounded: "{rounded.pane}"
  today-strip:
    textColor: "{colors.primary}"
    rounded: "20px"
  done-stamp:
    textColor: "{colors.primary}"
    rounded: "6px"
---

# Design System: Farash

## Overview

**Creative North Star: «شبنم» (dew on glass)**

The room has three soft lights: a peach lamp that moves to a new spot for each project, lavender across the room, and mint near the floor. By day the lights are bright pastels behind white frosted glass. At night the same hues sit low in a violet room.

The owner chose this world for #49 from a decision page of three looks: the "Lamp night" structure, with the "Glass day" colors and a dark version.

The structure is plain Material 3:
- **Top app bar:** medium, naming the project in Naskh. At night the title catches the light.
- **Today strip:** shows the real day's load, meaning the tasks due today and those late, with planned time. It only appears when something is due.
- **List card:** the open list sits in one glass card.
- **Capture bar:** floats over the list end.
- **Navigation:** a drawer on phones, and a glass navigation pane on wide screens.
- **Editor:** a side sheet on wide screens, and a bottom sheet on phones.

**Key Characteristics:**
- Three lights behind the glass: a moving peach lamp, lavender and mint.
- The open list in one glass card; glass only where content passes beneath, never nested.
- A medium top app bar with the project in Naskh.
- A today strip with real counts only.
- Violet means now; mint means tomorrow; rose means overdue. Near dates sit in tinted pills.

## Colors

Every color comes from `FarashPalette.dew` in `lib/app/palette.dart`. The palette feeds the Material theme, the backdrop, the glass and the priority marks.

- **Neutrals:** sheets, menus and dialogs are generated from the violet seed (`#5B45D6`).
- **Violet** (`primary`) is spent on "now":
  - today's dates and the today strip
  - the «انجام شد» stamp
  - the focused capture edge
  - the single primary action of a view
- **Mint** (`tertiary`) marks tomorrow.
- **Rose** (`error`) marks overdue and destructive actions.
- **Date pills:** today, tomorrow and late dates sit in a 14% pill of their own color; later dates stay plain.
- **Priorities:** red, orange, blue and grey, tuned per brightness, via `TaskPriority.colorIn(context)`.

Tests hold contrast in both themes:
- every text role at 4.5:1 or better on glass composited over each backdrop stop, and on the sheet surfaces
- priority marks at 3:1 or better

**The One Accent Rule.** If violet appears on something that is neither "now" nor the primary action, it is a bug.

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

**The room.** `GlassBackdrop` paints a soft vertical gradient with three radial blooms:
- **Lavender light:** fixed at the left middle.
- **Mint light:** fixed near the floor.
- **Peach lamp:** moves to a stable spot for each project over 900ms (easeInOutCubic) and holds still under reduced motion.

**The glass.** `GlassSurface` is a frosted pane:
- blur at sigma 20
- a 10% white tint at night (62% by day)
- a 1px light border
- a lit top edge
- an optional soft shadow (0 8px, blur 24px) for floating panes

The open list is one glass card (a decorated sliver, 24px radius, without blur), with a soft shadow by day only. The app bar uses the same tint and blur as a flat band with a bottom hairline, and only fades in once content scrolls beneath it.

Solid surfaces (drawer, bottom sheets, dialogs, menus) sit over a scrim and use the violet `surfaceContainer` roles.

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
- It is edged in violet while focused.
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
- Do take every color from `FarashPalette.dew`, priorities included.
- Do use glass only where content passes beneath it, and keep light behind it.
- Do name the current project in the app bar on every width.
- Do open editing as a side sheet beside the list on wide screens and as a modal bottom sheet on phones.
- Do keep violet for "now" and the primary action.
- Do stamp completions before folding them.
- Do honor reduced motion: the lamp, rows and bar hold still.

### Don't:
- Don't nest glass in glass, or put a boxed field or card inside a pane.
- Don't frame the whole phone screen in a pane.
- Don't float the editor as a short card inside the list.
- Don't add texture patterns to the glass. The #47 pebble relief read as noise.
- Don't add eyebrow labels above titles or tiny floating labels over the editor title.
- Don't spend violet on secondary buttons, icons or selection.
- Don't introduce controls for unimplemented features.
- Don't claim hardware or accessibility-service validation from source inspection.
