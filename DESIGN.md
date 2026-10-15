---
name: Farash Garden
description: A botanical sanctuary where confirmed completed work becomes visible growth.
colors:
  day-primary: '#315D47'
  day-surface: '#F8F6EE'
  day-ink: '#23362C'
  day-muted-ink: '#536356'
  day-selected: '#DEEADB'
  primary: '#ABD4AD'
  surface: '#14251F'
  ink: '#EDF1E6'
  muted-ink: '#BCCABD'
  selected: '#2D4937'
typography:
  heading: {fontFamily: Vazirmatn, fontSize: 28, fontWeight: 700}
  body: {fontFamily: Vazirmatn, fontSize: 16}
rounded: {control: 12, surface: 16}
spacing: {compact: 8, standard: 16, page: 24}
---

# Farash Garden

The owner requested a fundamental replacement for the glass identity, studied Todoist, TickTick, Pomofocus and Forest, and explicitly selected a game-like garden as the central experience. This supersedes the old dew/glass world.

## Places

**باغچه** is the new default for devices without a saved start preference. The original miniature garden begins with a sapling and becomes a mature sanctuary at ten server-confirmed completed tasks. Flowers at 1, 5, 10, 25 and 50 completions are derived visual milestones, not spendable rewards. Undo restores progress and its corresponding scene. Level and XP come from the account API; unavailable data never produces a fabricated score. Up to three real next tasks can be opened, completed with undo or used as a focus-session title.

**کارها** retains inbox, projects, labels, sections, dates, priorities, selection, ordering, editing and reversible completion. Flat task rows replace glass frames. The capture field remains above bottom navigation and safe areas, with measured scrolling clearance.

**تمرکز** has one dominant timer and focus/short-break/long-break modes. Its controller belongs to the signed-in shell: navigation preserves it; sign-out disposes it. A deadline catches up after tick suspension. Sessions are local and end when the app closes. This delivery does not claim background alarms, persistent focus history or focus XP.

Phones have three bottom destinations plus a project drawer. Wide layouts have a solid sidebar with the same destinations and project hierarchy. Existing saved start preferences remain respected; Garden is added to the preference dialog.

## Material

Cream and sage by day, pine and pale green at night. Warm earth marks future dates; rose marks late/error states. Every color flows from `FarashPalette.garden`. Surfaces are opaque. No ambient gradients, title glow or decorative glass/blur. Legacy `Glass*` class names are internal compatibility shims rendering solid Material surfaces.

Vazirmatn owns every text role. Persian/RTL is primary, with Persian digits. The timer is isolated LTR. Text scales with user settings; the large timer scales down to fit its width. Controls keep at least 48 logical pixels of touch area. Cards/control radii are 12–16. Only a short growth-stage crossfade is used, honoring reduced motion.

## References and authority

Todoist: fast capture and clear task hierarchy (https://www.todoist.com/features).
TickTick: distinct task/planning/focus destinations (https://ticktick.com/features).
Pomofocus: one legible timer and one primary action (https://pomofocus.io/).
Forest: a consistent botanical world and emotionally legible growth (https://forestapp.cc/).

Official product pages were studied; Pomofocus and Forest were also inspected visually. No third-party artwork is bundled. The user selected the garden direction; the local concept helper ran degraded without catalog challengers. Implementation is code-led, preserving Flutter product behavior.

## Verification scope

Widget captures use synthetic fixture data and verify layout, not an actual user's progress. Cover phone, desktop, dark mode and 2× text. These are not Android device evidence. Android builds run in CI; hardware and accessibility-service validation remain separate.
