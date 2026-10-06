# Calm glass redesign (#34)

> Superseded by `docs/design/surfaces/app.md` («شیشهٔ مشجر», #47). Kept as the record of #34.

## Approval
The user requested glass, chose light/calm, chose image-first, then said
“continue” after the A + C recommendation. Build A's quiet project workspace
with C's desktop side editor and mobile bottom sheet. The generated comparison
board in the conversation is the visual reference, not a shipping bitmap.
No generated search/settings icons are introduced without their functionality.

## Direction contract
THESIS: a luminous, quiet desk for capturing and arranging real tasks.
OWN-WORLD: warm ivory with a pomegranate primary and straw accent (#43; teal
until then), milky translucent navigation and
workspace panes, soft offset elevation, Vazirmatn and Persian RTL.
STORY: select a project, read its list, capture at the bottom, edit beside it.
FIRST VIEWPORT: a right project pane and centered readable list on desktop;
one full-width list on phone. The capture bar occupies layout space above the
keyboard. Wide editing opens a 380px pane, narrow editing opens a scrollable sheet.
FORM: A's floating glass workspace with C's detail composition. Illumination is
code-native color, not a decorative image; task text and controls remain semantic.
FINISH: independent finish review, actual widget captures and durable design docs;
no hardware/emulator claim. Reduced motion skips authored entrance/selection motion.

## Implementation constraints
48px controls, no per-row backdrop blur, 760px list measure, safe areas,
contrast over near-opaque text surfaces, preserve sections/reorder/undo/auth.

## Refinement pass (#41)
Same world, firmer hierarchy:
- **List:** the project name heads the list in large type with its open count,
  and the completed filter sits beside it. The phone app bar keeps only
  navigation.
- **Rows:** separated by a hairline from the title's edge. Priority shows only
  as the checkbox color. The drag handle is muted; on pointer screens it shows
  beside the checkbox on hover, and on touch screens it stays at the row's end.
- **Capture:** one rounded field holds the text, priority and send.
- **Editor:** a borderless heading title and notes, then property rows
  (schedule, priority as one segmented row, project, section). Checklist and
  subtask fields open on demand. Counters appear only near the limit.
- **Sidebar:** the app name sits over the account email, one account menu
  replaces the separate calendar and logout icons, and row menus show on hover
  for pointers.

## Palette and motion (#43)
- **Palette:** every color comes from `lib/app/palette.dart`. Pomegranate
  ships in light and dark: primary `#A6324A` / `#FFB0BE`, accent `#9C5C14` /
  `#EDBB72`, on ivory `#FFFBF8` / plum-dark `#2A1B1F`. A test keeps the text
  roles at 4.5:1 or better.
- **Color with meaning:**
  - Today's due date uses the primary color, tomorrow the accent, overdue the
    error color.
  - Each project's color or icon sits beside its title.
- **Motion** (`lib/app/motion.dart`): 160 ms for small state changes and
  280 ms for rows and pages, easing out on entry and in on exit.
  - A checked row pops its check, lingers 220 ms, then folds away.
  - New rows grow in.
  - Changing project fades through.
  - The subtask chevron turns, and send wakes up when there is text.
  - With reduced motion every one of these is instant.

## Compact-height capture
When available project-pane height falls below 240px, capture moves from its
normal bottom layout position to the top of the same CustomScrollView as tasks.
A GlobalKey preserves the draft across relocation. This keeps landscape-keyboard
layouts scrollable without reserving a fixed capture footer. GlassSurface's
transparent Material lets ListTile ink paint above the pane tint. These notes
describe source behavior and make no CI, hardware or accessibility-service claim.

## Editor and status adaptations
Nonexpanding property rows stack heading and control below 480px available width.
PriorityPicker retains minimum 48px targets and switches to vertical below 320px
when textScaler.scale(14) exceeds 18px; typography is not fitted down. Compact
capture remains mounted above loading/error slivers, and empty-state copy is
direction-independent. These are implementation descriptions, not validation
results.
