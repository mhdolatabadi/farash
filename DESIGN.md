---
name: Farash
description: A warm, luminous Persian task workspace.
colors:
  primary: "#A6324A"
  on-primary: "#FFFFFF"
  accent: "#9C5C14"
  surface: "#FFFBF8"
  ink: "#2D1C20"
  muted-ink: "#6E5A5D"
  selected: "#F5DFE2"
  on-selected: "#5C1023"
  glow: "rgba(255, 255, 255, 0.701961)"
  pane: "rgba(255, 255, 255, 0.721569)"
  pane-border: "rgba(255, 255, 255, 0.901961)"
  shadow: "rgba(45, 28, 32, 0.078431)"
  backdrop-1: "#F4DFDF"
  backdrop-2: "#FDF9F4"
  backdrop-3: "#F1E6D2"
  dark-primary: "#FFB0BE"
  dark-on-primary: "#5C1023"
  dark-accent: "#EDBB72"
  dark-surface: "#2A1B1F"
  dark-ink: "#F6E8EA"
  dark-muted-ink: "#CDB8BB"
  dark-selected: "#4E2A32"
  dark-on-selected: "#F6E8EA"
  dark-glow: "rgba(140, 58, 76, 0.200000)"
  dark-pane: "rgba(42, 27, 31, 0.901961)"
  dark-pane-border: "rgba(255, 176, 190, 0.160784)"
  dark-shadow: "rgba(0, 0, 0, 0.301961)"
  dark-backdrop-1: "#3A1A22"
  dark-backdrop-2: "#1A1114"
  dark-backdrop-3: "#2B2216"
typography:
  project-headline:
    fontFamily: "Vazirmatn"
    fontSize: "24px"
    fontWeight: 800
  editor-heading:
    fontFamily: "Vazirmatn"
    fontSize: "24px"
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
  input:
    rounded: "{rounded.control}"
    padding: "14px 16px"
    textColor: "{colors.ink}"
  navigation-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.on-selected}"
    rounded: "{rounded.control}"
  glass-pane:
    backgroundColor: "{colors.pane}"
    rounded: "{rounded.pane}"
---

# Design System: Farash

## Overview

**Creative North Star: "The Quiet Desk"**

A luminous, quiet desk for capturing and arranging real tasks. The current pomegranate world pairs warm ivory and straw illumination with milky glass panes and plum ink. The user-approved calm glass direction remains the foundation; the current palette and stronger hierarchy come from the implemented refinements.

Persian RTL and bundled Vazirmatn define the app's identity across Android and Web. Semantic task content, clear project hierarchy and reversible actions remain central. The comparison board is a reference, not shipping artwork.

**Key Characteristics:**
- Warm ivory glass with pomegranate actions and straw accents.
- Strong project headings above restrained task rows.
- Persian-first reading and semantic controls.
- Short purposeful motion with instant reduced-motion behavior.

## Colors

Primary is pomegranate for actions and today's due date. The straw accent supplies tomorrow's date; overdue dates use the generated Material error role. Plum ink and muted ink distinguish titles from metadata. Selected navigation uses a rose tonal surface. Dark mode uses pale pink actions and straw on plum-dark panes.

Frontmatter extracts the actual palette from lib/app/palette.dart, including ARGB alpha as CSS rgba. Remaining Material roles are generated with tonalSpot from the palette primary; do not assign invented fixed colors to those roles. Project colors and icons remain meaningful per-project identifiers.

**The Meaningful Color Rule.** Keep temporal color and project identity tied to actual task data; priority is represented by the check color, not a decorative P badge.

## Typography

Vazirmatn supplies all text through Material 3 roles. App identity and project list headings use headlineSmall with weight (800). The editor title uses headlineSmall with weight (700), reads as a borderless heading, and accepts up to four lines. Task titles use bodyLarge, up to three lines; description previews use bodySmall and one line. Metadata uses labelMedium. Counters appear near field limits rather than constantly.

**The Persian Reading Rule.** Preserve RTL and directional spacing, while explicitly isolating account email as LTR.

## Layout

Persistent navigation begins at a viewport width of (840px), with a (280px) sidebar, (20px) shell inset and (16px) pane gap. Phones use a drawer and a full-width workspace. Task content has a maximum measure of (760px). The project name and open count head the list; the phone app bar holds navigation.

Editing uses available project-pane width: at (820px), a (380px) editor sits beside the list with a (12px) gap. Narrow initial openings use a scrollable bottom sheet; an already-open inline editor occupies the pane when narrowed. Editor padding includes keyboard insets.

Capture normally occupies layout space below the list. The compact-height adaptation moves capture above tasks in their shared CustomScrollView when available project-pane height is below (240px); a GlobalKey preserves its draft across relocation. Compact capture remains mounted above loading and error slivers too; empty-state wording does not depend on text direction.

**The Reachable Control Rule.** Preserve (48px) action targets for completion, icon actions and primary buttons, even when the visual check is smaller.

## Elevation & Depth

GlassSurface bounds backdrop blur to large panes, with default sigma (16). Palette-defined pane tint, border and shadow govern both modes. An offset shadow (0px 10px, blur 28px) surrounds the clipped pane; transparent Material inside the decorated fill lets ListTile ink paint above the glass. Cards retain zero Material elevation. Code-native diagonal gradients and radial glow create ambient illumination.

Motion uses (160ms) small state changes, (280ms) rows and pages, and a (220ms) completed-row linger before folding. Entry uses easeOutCubic; exit uses easeInCubic. New rows grow/fade/slide from a vertical offset (0.15); project changes fade through. Checks pop with easeOutBack, subtasks turn their chevron and send activates with text. Individual fill transitions still use (150ms). Authored durations become zero under reduced motion.

**The Bounded Glass Rule.** Blur large workspace and navigation panes, never every task row.

## Shapes

Controls have softly squared corners (12px), standard cards and floating actions (16px), mobile workspaces (20px), and large panes, sheets and dialogs (24px). Drawers curve the exposed left edge in RTL. A circular visible completion check sits within its larger action target. Task hairlines start at the title edge rather than cutting across the check.

## Components

Primary and outlined actions share control shape and minimum height. Primary labels are bold; generated Material state layers provide default interactions. Filled fields use generated surfaceContainerHighest at half opacity, with (14px 16px) padding and a (2px) primary focus stroke.

The capture bar is one rounded field holding task text, priority and send. Navigation combines project color/icon, semantic title and tonal selection. The app name sits above account email; one account menu handles account actions. Pointer row menus and drag handles reveal on hover; touch keeps drag at the row end.

Task rows remain flat and show title, description preview, checklist/subtask counts and actual dates when present. Completion retains a strike-through and supporting-ink text. Subtasks indent directionally and fold through a chevron. Selection and row actions use semantic widgets.

The editor begins with borderless title and notes, followed by property rows for schedule, segmented priority, project and section. Nonexpanding property rows stack their heading above the control below (480px) available width. Priority segments retain a minimum (48px × 48px) target and switch to vertical when available width is below (320px) and the text scaler renders a (14px) label above (18px). Text uses its configured scale rather than fitting it down. Checklist and subtask fields open on demand. Close, save and deletion operate on actual task state. Authentication shares the glass vocabulary.

## Do's and Don'ts

### Do:
- Do preserve Persian RTL and bundled Vazirmatn.
- Do use the pomegranate palette source for light and dark roles.
- Do keep task content, dates and controls semantic.
- Do preserve capture drafts when adapting to keyboard-constrained height.
- Do honor reduced motion for authored animations.

### Don't:
- Don't blur each task row.
- Don't restore obsolete teal tokens or priority P badges.
- Don't ship the comparison board as interface artwork.
- Don't introduce controls for unimplemented features.
- Don't claim hardware or accessibility-service validation from source inspection.
