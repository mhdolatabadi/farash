---
name: Menval Ledger
description: A contemporary Persian daily planner with an editorial daybook rhythm, warm paper, dark ink, cinnabar action, fine rules, and restrained elevation.
colors:
  day-primary: '#9F3F2D'
  day-on-primary: '#FFFFFF'
  day-primary-container: '#F5DBD1'
  day-on-primary-container: '#742A1C'
  day-accent: '#21645E'
  day-surface: '#FCFAF6'
  day-ink: '#292722'
  day-muted-ink: '#66635D'
  day-container-low: '#F4F0E9'
  day-container: '#EEE8DF'
  day-outline: '#9C9488'
  day-divider: '#DDD5C9'
  primary: '#FFB69B'
  on-primary: '#43261F'
  primary-container: '#56382F'
  on-primary-container: '#FFE2D6'
  accent: '#8DD1C3'
  surface: '#191F1D'
  ink: '#F5F0E9'
  muted-ink: '#B8B5AB'
  container-low: '#222925'
  container: '#2A332E'
  outline: '#869287'
  divider: '#414A43'
typography:
  family: Vazirmatn
  editorialDate: {fontSize: 68, fontWeight: 900, tabular: true}
  screenTitle: {fontSize: 24, fontWeight: 800}
  body: {fontSize: 16, lineHeight: 1.5}
  secondary: {fontSize: 13}
rounded: {field: 12, surface: 16, tile: 18, sheet: 24, button: 14}
spacing: {xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32, gutter: 16, keyline: 56}
---

# Menval Ledger · دفتر روزها

## Intent

Menval is a private, Persian-first task and planning app. The user explicitly asked to discard the incumbent look and redesign it from the ground up. This replaces *Menval Calm*, its equal-weight neumorphic bento cards and lime-on-black/teal-on-grey visual grammar. It does **not** replace the product, data model, interactions, account boundaries, Persian-first content or Android installation identity.

Our new visual point of view is the **contemporary daybook**: a clear place to record and finish work, with the authority of good Persian editorial typography, rhythm and ample margins. Its cultural reference is a thoughtfully typeset notebook or agenda, not a literal diary imitation. No simulated paper texture, faux bookbinding, rug drawings, gradients, glass, or ornamental marketing illustrations.

## Identity

- **Ground:** warm white paper in light mode; deep green-charcoal ink in dark mode. Both are intentional backgrounds, not elevated slabs.
- **Ink:** near-black body text with explicit content hierarchy; muted ink only for genuinely secondary information.
- **Action:** one cinnabar/terracotta primary color for check state, main CTA, focus and selected navigation. Dark mode uses its light coral analogue. A reserved green-teal accent identifies near-future dates without competing for attention.
- **Mark:** a simple Persian «م» in a square signet. It scales as a normal vector/text mark and does not replace any platform icons or accessible labels.
- **Depth:** list surfaces are bordered and quiet, never inset shadows. A small downward soft shadow is allowed on transient panes; no double-direction neumorphism.
- **Shape:** restrained rounded rectangles (12–18), not universally oversized pills. Visible focus and pressed states stay Material-native.
- **Typography:** bundled Vazirmatn, Persian digits and RTL. Date and page titles lead; task content is the centre. Large numbers use tabular figures when appropriate.

## Layout and hierarchy

### Today
1. A large, expressive date and weekday as a typographic heading.
2. A single compact daily overview: only confirmed progress, an optional focus shortcut with a live countdown, and honest open-task count.
3. Task list and overdue tasks immediately visible; rows get more room and remain directly actionable.
4. One quick capture field fixed above bottom navigation/safe area. Its focus, error and disabled states are explicit.

### Other destinations
- **Inbox/projects:** compact editorial list headers, task-first rows, clear priority circles, minimal metadata only when relevant.
- **Focus:** timer is the focal content, secondary actions don't compete with start/pause. No unrelated floating control blocking the dial.
- **Calendar:** native date navigation with stable task/event separation and consistent task detail entry.
- **Time and habits:** same card, type and color tokens, but visualizations are data-first and never invent results.
- **Desktop:** a stable sidebar and measure-limited task canvas, not stretched oversized cards.

## Components and states

- `SoftTile` and `SoftWell` retain their API for migration but render clean Ledger surfaces; `Panel` follows those rules.
- Buttons have 48dp minimum touch targets; visual icons may be smaller but tap regions are not.
- Empty states point at the next real action. Loading, error, offline, keyboard/IME, focused and disabled states remain readable.
- Primary tasks and quick capture should be above the fold on a normal phone with real sample data, including 320px widths.
- At 1.3× and 2× text scales, content wraps/stacks instead of clipping or hiding actions.
- Keep semantic labels, tooltip parity, RTL ordering, Persian digits and selected states.
- No fabricated completion count, token status, time tracking, provider event or upcoming feature.

## Delivery and rollout

PR #258 initiates the V2 visual foundation, shared components and Today. Subsequent PRs must migrate detail/Focus/calendar/time/sidebars and visual QA in that order, while preserving all existing behavior. Every PR has narrow and wide Android/web capture checks, light/dark coverage and regression tests. Keep the previous theme on `main` until CI and real screenshots show that the new system improves legibility. Roll back by reverting the isolated V2 UI PR; no persistence/API/data migration is involved.
