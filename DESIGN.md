---
name: Farash Weaving
description: A Persian weaving atelier where confirmed completed work becomes visible craft.
colors:
  day-primary: '#98503D'
  day-surface: '#FAF5EB'
  day-ink: '#283442'
  day-muted-ink: '#69625B'
  day-selected: '#F0DDD2'
  day-accent: '#246D72'
  day-error: '#B3263A'
  day-container-lowest: '#FFFCF6'
  day-container-low: '#FFFAF2'
  day-container: '#F1E7D9'
  day-container-high: '#EADCCA'
  day-outline: '#DDCBB6'
  primary: '#F2B49A'
  surface: '#19232F'
  ink: '#F5EDE1'
  muted-ink: '#CFC3B7'
  selected: '#553B34'
  accent: '#86CCD0'
  error: '#FF9AA6'
  container-lowest: '#16202B'
  container-low: '#22303D'
  container: '#2A3744'
  container-high: '#33414E'
  outline: '#52606A'
typography:
  weaving-heading: {fontFamily: Vazirmatn, fontSize: 28, fontWeight: 700, lineHeight: 1.35}
  body: {fontFamily: Vazirmatn, fontSize: 16}
  timer: {fontFamily: Vazirmatn, fontSize: 80, fontWeight: 700}
rounded: {chip: 14, control: 18, progress: 20, surface: 22, panel: 24}
spacing: {compact: 8, standard: 16, page: 24}
---

# Design System: Farash Weaving

## Overview

**Creative North Star: "A Persian weaving atelier"**

The owner explicitly rejected similarity to Forest and approved an original Persian woven-rug world. This supersedes the botanical and earlier dew/glass identities. Confirmed work becomes visible woven craft; task utility and a legible focus timer support the atelier. The same high artistic quality is a durable expectation across the UI, including quiet utility surfaces, rather than only the home illustration.

**Key Characteristics:**
- Woven rows grounded in confirmed completed work.
- Wool cream, terracotta and turquoise by day; midnight ink at night.
- Persian-first typography and reversible, direct actions.

## Colors

Wool cream, terracotta and turquoise by day; midnight ink at night. Frontmatter names prefixed `day-` describe light mode; unprefixed counterparts describe dark mode.

### Primary

Terracotta identifies the primary action and timer, with pale warm primary tones at night. Selected rows and chips use the warm selected surface with readable ink.

### Secondary

Turquoise marks future dates; rose marks late/error states. Priority colors retain their separate red, orange, blue and muted hierarchy from `FarashPalette.weaving`.

### Neutral

Surface, ink and muted ink come from the palette. Lowest, low, regular and high Material containers and the outline variant are explicitly warm in light mode and blue-slate in dark mode. Other Material roles, including the highest container used by field fill, are generated from the active primary seed. Input fill is a translucent tonal container over an opaque surface.

**The Confirmed Weaving Rule.** Never fabricate progress, XP or rewards to decorate a screen.

## Typography

Vazirmatn owns every text role. Persian/RTL is primary, with Persian digits. The weaving heading is the Material headline-medium role with bold weight; the body token describes body-large, while compact supporting text uses the remaining Material text roles. Headline roles have a line height of 1.35. These are Flutter logical measurements, not web pixel requirements.

The timer uses bold display text, isolated LTR and scaled down to fit its width. Text follows user scaling; narrow layouts must retain readable task content.

## Layout

Phones have three bottom destinations plus a project drawer. At a shell width of 840 logical pixels, a solid sidebar replaces bottom navigation; its content width is 288. Weaving content is centered within 960, with 24 horizontal padding. Above 650 available content width, scene and next tasks sit beside each other at a 6:4 ratio with a 40 gap; otherwise they stack. Focus content is centered within 620.

The capture field remains above bottom navigation and safe areas, with measured scrolling clearance. Preserve existing saved start preferences and migrate the persisted `garden` value to `weaving`; Weaving is the default when no preference exists.

## Elevation & Depth

Opaque tonal surfaces, warm outlines, original artwork and restrained lift create depth. Theme cards retain zero Material elevation, while `AtelierPanel` adds an ambient shadow (offset 0, 7; blur 22; black alpha .045 by day and .12 by night). Panels can opt out of lift. Legacy `Glass*` names are compatibility shims; the visual material is opaque atelier paper. No ambient gradients, title glow or decorative glass/blur.

The labelled rug pattern reveals rows over 320 ms; the decorative loom image is static. Shell changes also fade and scale using the standard 280 ms motion; task rows have arrival and completion motion. `Motion.of` removes these durations when reduced motion is requested. Material controls retain their framework state behavior.

## Shapes

Controls and individual task surfaces use rounded corners (18); theme cards and capture use 22. Chips use 14, the weaving progress card uses 20, and atelier panels default to 24. Drawers, sheets and dialogs use 24 where defined by the theme. Component-specific radii remain intentional rather than a universal pill. Filled, outlined and text buttons have a minimum height of 48; icon buttons have a minimum 48 by 48 area.

## Components

### Buttons

Solid terracotta primary buttons use bold Material labels and the control radius. Secondary text actions use ink. Preserve Material hover, focus, pressed and disabled feedback; do not introduce decorative glow.

### Chips

Selected chips use the selected surface and corresponding ink; chip icons use muted ink. Unselected chips use the low container with a warm outline and 14 radius. Focus-mode chips are disabled while the timer runs.

### Cards / Containers

Theme cards use the explicit `surfaceContainerLow`, outline borders, the surface radius and zero elevation. Task rows are individual 18-radius solid surfaces with subtle outline borders and selected tonal fills. `AtelierPanel` carries lifted page furniture, focus framing and capture; ornamental `ThreadRule` dividers use the house diamond between fine lines.

### Inputs / Fields

Filled tonal fields use the control radius, 16 horizontal and 14 vertical padding. Focus uses a primary border of width 2; errors use the theme error role.

### Navigation

فرش, کارها and تمرکز are directly reachable. Phone navigation is 72 high with selected tonal indicators and a fine top border; the weaving destination uses the original nested-diamond `WeaveMark`. The same mark identifies the account header. Toolbars pair their title with a tonal icon badge. Wide layouts use the same destinations and project hierarchy in the sidebar.

### Weaving and Focus

The transparent original loom illustration (`assets/weaving/loom.png`) establishes atmosphere and is decorative. Actual progress is carried by the labelled `RugPattern` card, not the illustration. Each confirmed completed task represents one row. Fifty rows complete one rug: current rows equal completed count modulo 50, and collection count equals completed count divided by 50, rounded down. At exactly 50, one rug enters the collection and the next begins at zero rows. Undo deterministically removes the corresponding row or completed rug. The current and collected rugs repeat one original authored rug image (`assets/weaving/rug.png`); there are no distinct palette variants. `RugPattern` reveals its exact bottom-up completion fraction using a clip over pale drawn warp. It does not encode project history or project-specific threads. One collected rug is displayed large at 35% of viewport height; multiple rugs use a lazy grid within 45% of viewport height, inside a scrollable dialog capped at width 520.

Level and XP come from the account API; unavailable data never produces a fabricated score or rug progress. Up to three real next tasks can be opened, completed with undo or used as a focus-session title.

Focus frames the timer in an atelier panel with thread-rule ornaments and retains one dominant timer and focus/short-break/long-break modes (25/5/15 minutes). Its controller belongs to the signed-in shell: navigation preserves it; sign-out disposes it. A deadline catches up after tick suspension. Sessions are local and end when the app closes. This delivery does not claim background alarms, persistent focus history or focus XP. Starting focus for a different task while a session runs preserves the running session and explains this through a snackbar.

## Do's and Don'ts

- Do derive woven rows and collection counts from confirmed completed work and retain undo.
- Do preserve Persian RTL, Persian digits and the isolated LTR timer.
- Do keep task content readable with user text scaling.
- Don't restore decorative glass, ambient gradients or title glow.
- Don't display unavailable account progress as an invented score.
- Don't infer project-specific threads, colors or historical rugs from unavailable completion history.
- Don't present the static loom illustration as the measured progress display.

Reference authority and surface strategy live in `docs/design/weaving.md`; durable product constraints live in `PRODUCT.md`.
