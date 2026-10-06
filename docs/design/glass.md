# Calm glass redesign (#34)

## Approval
The user requested glass, chose light/calm, chose image-first, then said
“continue” after the A + C recommendation. Build A's quiet project workspace
with C's desktop side editor and mobile bottom sheet. The generated comparison
board in the conversation is the visual reference, not a shipping bitmap.
No generated search/settings icons are introduced without their functionality.

## Direction contract
THESIS: a luminous, quiet desk for capturing and arranging real tasks.
OWN-WORLD: pale mist and ivory, deep teal ink, milky translucent navigation and
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
