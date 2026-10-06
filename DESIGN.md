---
name: Farash
description: Patterned privacy glass at night: the day's tasks behind the lamp-lit glass of an Iranian home.
colors:
  primary: "#E8B66B"
  on-primary: "#21170A"
  accent: "#A9C4B2"
  overdue: "#EF8C8F"
  surface: "#141B36"
  ink: "#F3ECE2"
  muted-ink: "#B9B2A6"
  selected: "#26305A"
  on-selected: "#F3ECE2"
  backdrop-1: "#17204A"
  backdrop-2: "#0F1530"
  backdrop-3: "#0A0E1F"
  glow: "rgba(232, 182, 107, 0.32)"
  pane: "rgba(232, 228, 240, 0.06)"
  pane-border: "rgba(255, 236, 206, 0.15)"
  relief: "rgba(255, 244, 226, 0.03)"
  relief-shade: "rgba(0, 0, 0, 0.07)"
  shadow: "rgba(0, 0, 0, 0.35)"
  day-primary: "#8A5A12"
  day-on-primary: "#FFFFFF"
  day-accent: "#3F6B52"
  day-overdue: "#B3343F"
  day-surface: "#FBF8F2"
  day-ink: "#1E2230"
  day-muted-ink: "#5A5E6B"
  day-selected: "#EDE5D5"
  day-on-selected: "#1E2230"
  day-backdrop-1: "#E9ECF3"
  day-backdrop-2: "#F6F2EA"
  day-backdrop-3: "#EFE3CF"
  day-glow: "rgba(240, 194, 122, 0.45)"
  day-pane: "rgba(255, 255, 255, 0.60)"
  day-pane-border: "rgba(255, 255, 255, 0.85)"
  day-relief: "rgba(255, 255, 255, 0.06)"
  day-relief-shade: "rgba(30, 34, 48, 0.03)"
  day-shadow: "rgba(30, 34, 48, 0.08)"
typography:
  heading:
    fontFamily: "Noto Naskh Arabic (FarashNaskh), Vazirmatn"
    fontSize: "24px"
    fontWeight: 700
    lineHeight: 1.35
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
  mobile-workspace: "20px"
  pane: "24px"
spacing:
  compact: "8px"
  pane-gap: "12px"
  standard: "16px"
  shell: "20px"
  spacious: "24px"
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
  input:
    rounded: "{rounded.card}"
    padding: "14px 16px"
    textColor: "{colors.ink}"
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

**Creative North Star: «شیشهٔ مشجر» (patterned privacy glass at night)**

The day's tasks are seen through the pressed, patterned glass of an Iranian home's door at night. Indigo night lies in front, and a lamp-lit room glows behind the glass. Panes are frosted with a faint pebble relief and a lit top edge, and the lamp moves to a new place when the project changes. The world was chosen in #47 through the impeccable direction roll (seed 3a5bd5db, candidate 7). The direction contract lives in `docs/design/surfaces/app.md`.

Night is the designed default; day is the same door by daylight. Persian RTL, bundled Vazirmatn and the reversible, semantic task model remain from earlier worlds.

**Key Characteristics:**
- Indigo night ground with a moving honey lamp behind the glass.
- Frosted panes with a faint pressed-pebble relief and a lit top edge.
- Naskh headings, Vazirmatn reading text, tabular figures.
- Honey means now; sage means tomorrow; pomegranate means overdue.
- Checked tasks are stamped «انجام شد» before they fold away.

## Colors

Every color comes from `FarashPalette.moshajjar` in `lib/app/palette.dart`, which feeds both the Material theme and the glass backdrop and panes.

- **Honey** (`primary`, the lamplight) is spent only on "now": today's dates, the «انجام شد» stamp, and the single primary action of a view (save, send).
- **Sage** (`tertiary`) marks tomorrow.
- **Pomegranate** (`error`) marks overdue and nothing else.
- **Ink:** lamp-lit ink for text and muted ink for metadata.
- **Selection:** a deeper night tone. Secondary text actions and chip icons take the ink.

Day mode keeps the same roles at contrast-safe values. A test holds every text role at 4.5:1 or better on its surface in both themes.

**The One Lamp Rule.** If honey appears on something that is not "now" or the primary action, it is a bug.

## Typography

Headings (`displaySmall`, `headline*`) are set in Noto Naskh Arabic Bold, bundled as `FarashNaskh` (OFL), with Vazirmatn as fallback and a 1.35 line height. That covers the project heading, the app name and the editor's title.

Everything read in passing stays in Vazirmatn through the Material 3 roles:
- **Task titles:** bodyLarge, up to three lines.
- **Previews:** bodySmall, one line.
- **Metadata:** labelMedium.

Counters appear only near field limits.

**The Persian Reading Rule.** Preserve RTL and directional spacing, while explicitly isolating account email as LTR.

## Layout

Persistent navigation begins at a viewport width of (840px), with a (280px) sidebar, (20px) shell inset and (16px) pane gap. Phones use a drawer and a full-width workspace. Task content has a maximum measure of (760px). The project name and open count head the list; the phone app bar holds navigation.

Editing uses available project-pane width: at (820px), a (380px) editor sits beside the list with a (12px) gap. Narrow initial openings use a scrollable bottom sheet; an already-open inline editor occupies the pane when narrowed. Editor padding includes keyboard insets.

Capture normally occupies layout space below the list. The compact-height adaptation moves capture above tasks in their shared CustomScrollView when available project-pane height is below (240px); a GlobalKey preserves its draft across relocation. Compact capture remains mounted above loading and error slivers too; empty-state wording does not depend on text direction.

**The Reachable Control Rule.** Preserve (48px) action targets for completion, icon actions and primary buttons, even when the visual check is smaller.

## Elevation & Depth

GlassSurface bounds blur (sigma 16) to the large panes and never blurs each row.
- **Pane fill:** each pane takes the palette's pane tint and hairline border.
- **Lit edge:** a gradient across the top fifth of the pane.
- **Relief:** a pressed-pebble pattern on a staggered 13px grid of 1.6px domes, lit top-left and shaded bottom-right, painted once on its own layer so scrolling never repaints it.
- **Shadow:** a soft offset shadow (0 12px, blur 32px) lifts the pane off the night.

GlassBackdrop paints the indigo ground and a honey radial glow (radius 0.75). The lamp moves to a stable position per project over 900ms (easeInOutCubic) and holds still under reduced motion.

Motion uses 160ms for small state changes, 280ms for rows and pages, and a 220ms linger for a completed row, which is stamped «انجام شد» (160ms easeOutBack press) before it folds. Entry eases out (easeOutCubic) and exit eases in (easeInCubic). New rows grow in, project changes fade through, and checks pop. All authored durations become zero under reduced motion.

**The Faint Relief Rule.** The relief stays at a few percent alpha; text always sits on calm glass.

## Shapes

Controls have softly squared corners (12px), standard cards and floating actions (16px), mobile workspaces (20px), and large panes, sheets and dialogs (24px). Drawers curve the exposed left edge in RTL. A circular visible completion check sits within its larger action target. Task hairlines start at the title edge rather than cutting across the check.

## Components

Primary and outlined actions share control shape and minimum height. Primary labels are bold; generated Material state layers provide default interactions. Filled fields use generated surfaceContainerHighest at half opacity, with (14px 16px) padding and a (2px) primary focus stroke.

The capture bar is one rounded field holding task text, priority and send. Navigation combines project color/icon, semantic title and tonal selection. The app name sits above account email; one account menu handles account actions. Pointer row menus and drag handles reveal on hover; touch keeps drag at the row end.

Task rows remain flat and show title, description preview, checklist/subtask counts and actual dates when present. Completion retains a strike-through and supporting-ink text. Subtasks indent directionally and fold through a chevron. Selection and row actions use semantic widgets.

The editor begins with borderless title and notes, followed by property rows for schedule, segmented priority, project and section. Nonexpanding property rows stack their heading above the control below (480px) available width. Priority segments retain a minimum (48px × 48px) target and switch to vertical when available width is below (320px) and the text scaler renders a (14px) label above (18px). Text uses its configured scale rather than fitting it down. Checklist and subtask fields open on demand. Close, save and deletion operate on actual task state. Authentication shares the glass vocabulary.

## Do's and Don'ts

### Do:
- Do take every color from `FarashPalette.moshajjar`.
- Do keep honey for "now" and the primary action.
- Do set headings in Naskh and reading text in Vazirmatn.
- Do stamp completions before folding them.
- Do preserve capture drafts when adapting to keyboard-constrained height.
- Do honor reduced motion: the lamp and rows hold still.

### Don't:
- Don't spend honey on secondary buttons, icons or selection.
- Don't raise the relief until it reads as a perforated sheet.
- Don't blur each task row.
- Don't restore the pomegranate or teal worlds' tokens or priority P badges.
- Don't introduce controls for unimplemented features.
- Don't claim hardware or accessibility-service validation from source inspection.
