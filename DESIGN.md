---
name: Farash
description: A luminous, quiet desk for Persian task capture and organization.
colors:
  primary: "#17665E"
  on-primary: "#FFFFFF"
  ink: "#163D42"
  muted-ink: "#4A6869"
  surface: "#F5FAF8"
  selected: "#D1E9E4"
  mist: "#D7EEEB"
  ivory: "#F5F8F3"
  cool-mist: "#DAE9ED"
  dark-primary: "#9ADACF"
  dark-on-primary: "#102D2B"
  dark-ink: "#EAF5F2"
  dark-muted-ink: "#BDD1CE"
  dark-surface: "#1B3037"
  dark-selected: "#355650"
  dark-backdrop-start: "#193B40"
  dark-backdrop-middle: "#101E25"
  dark-backdrop-end: "#23343B"
  dark-glow: "#53847C"
typography:
  headline:
    fontFamily: "Vazirmatn"
    fontSize: "24px"
    fontWeight: 700
  title:
    fontFamily: "Vazirmatn"
    fontSize: "22px"
    fontWeight: 700
  body:
    fontFamily: "Vazirmatn"
    fontSize: "16px"
  label:
    fontFamily: "Vazirmatn"
    fontSize: "14px"
    fontWeight: 700
rounded:
  control: "12px"
  card: "16px"
  mobile-workspace: "20px"
  glass: "24px"
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
    typography: "{typography.label}"
  input:
    rounded: "{rounded.control}"
    padding: "14px 16px"
    textColor: "{colors.ink}"
  navigation-selected:
    backgroundColor: "{colors.selected}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
  glass-pane:
    backgroundColor: "rgba(255,255,255,0.78)"
    rounded: "{rounded.glass}"
---

# Design System: Farash

## Overview

**Creative North Star: "The Quiet Desk"**

A luminous, quiet desk for capturing and arranging real tasks. Pale mist and ivory light surround milky panes; deep teal ink gives semantic task content clear hierarchy. This captures the user's light, calm glass direction and the implemented Flutter system, rather than the generated comparison image.

Persian RTL and bundled Vazirmatn are durable identity commitments. Android and Web share the same visual vocabulary; the coordinated dark theme changes illumination and ink while keeping structure and controls consistent.

**Key Characteristics:**
- Milky large panes over code-native ambient illumination.
- Readable task rows with restrained hierarchy.
- Persian-first typography and directional layout.
- Reversible actions and visible, semantic task controls.

## Colors

Primary is a deep, muted teal for action and focus. Neutral ink and muted ink separate task titles from supporting text. Mist, ivory and cool mist create the light backdrop; selected navigation uses a pale teal tonal surface.

Dark roles use luminous pale teal actions, light ink and muted supporting ink on blue-teal surfaces. Remaining Material roles, including outline, error and surface-container levels, come from Flutter's tonalSpot ColorScheme seeded by the app brand color; these are generated roles rather than manually fixed hex tokens.

**The Content First Rule.** Keep task text on the near-opaque surface and use illumination behind it, never as a replacement for semantic content.

## Typography

Vazirmatn supplies all app type. Typography inherits Material 3 roles: headlineSmall identifies the app, titleLarge names the project and editor, bodyLarge carries task titles, and bodySmall supports descriptions. Frontmatter records the observed role defaults and explicit bold overrides; it is not a new custom type scale. Task titles show up to three lines, descriptions one preview line, and completed titles retain text with a strike-through.

**The Persian Reading Rule.** Keep Persian content RTL, use directional spacing, and explicitly isolate account email as LTR.

## Layout

The shell switches to persistent project navigation at (840px). Its navigation pane measures (280px), shell inset (20px), and gap (16px). Narrow screens use a drawer and a full-width workspace with (12px) outer inset and (20px) corners. The list has a maximum readable measure of (760px).

Editing is governed by the available project-pane width, not viewport width: at (820px) the editor sits alongside the list at (380px), separated by (12px). Narrow initial openings use a scrollable bottom sheet; when an already-open inline editor loses available width, it occupies the project pane. Quick capture takes layout space below the list. Editor padding includes keyboard insets.

**The Reachable Control Rule.** Maintain (48px) action targets for icon buttons, primary buttons and task completion; visual check circles may remain smaller inside those targets.

## Elevation & Depth

GlassSurface clips blur to a few large panes: default blur sigma is (16), light fill opacity (0.78), dark fill opacity (0.90), with a fine white or muted teal border. Rows do not individually blur. Backdrop gradients and a radial glow provide ambient depth. Glass panes now carry an ambient offset shadow (0px 10px, blur 28px) with opacity (0.07) in light mode and (0.16) in dark mode. Material cards retain zero elevation.

Authored task-check selection motion lasts (150ms) and becomes zero when MediaQuery disables animations. Material default interactions remain governed by the framework.

**The Bounded Glass Rule.** Blur the workspace and navigation surfaces, never each task row.

## Shapes

Controls use softly squared corners; cards are slightly rounder, and large glass panes have the broadest curve. Drawers curve their exposed left edge in RTL; bottom sheets curve their top edge. The completion control is circular, with a (22px) visible check and (2px) stroke inside its action target.

## Components

Primary buttons use teal fill, contrasting on-primary text, bold labels and a minimum (48px) height. Outlined buttons share control shape and height. Disabled and interaction state layers follow Material 3.

Inputs are filled with a translucent generated highest-container role and use (14px 16px) padding. A (2px) primary border marks focus; errors use the generated error role. Navigation uses tonal selection, control corners and semantic project names.

Task rows remain flat. Completion offers a round priority-colored check; nondefault priorities also show a textual P label in the semantic supporting-ink color. Authentication also uses the same GlassSurface vocabulary. The editor carries real title, description, priority, project and section fields with close, save and delete actions. The quick-capture bar is a real one-field capture control beneath the list, rather than an image overlay.

## Do's and Don'ts

### Do:
- Do preserve Persian RTL and bundled Vazirmatn.
- Do keep task text, navigation and actions semantic.
- Do use large, near-opaque glass panes and readable task measures.
- Do preserve keyboard-aware capture and editor spacing.
- Do honor reduced motion for authored selection animations.

### Don't:
- Don't blur each task row.
- Don't ship the generated comparison board as UI artwork.
- Don't introduce decorative controls for unimplemented features.
- Don't claim hardware performance or accessibility-service validation from source inspection.
