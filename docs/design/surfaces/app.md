# Surface brief: the Farash app (all screens)

## Revision for #49: night glass (current)
The owner reviewed the #47 build and judged it not standard. An impeccable
critique ran as two independent sub-agent assessments: a design review and
detector plus capture evidence. It scored Consistency and Standards 1/4 and
found these problems:
- the phone screen framed in a pane
- glass nested in glass
- a phone bar with no title
- the wide-screen editor as a short floating card
- blur with nothing behind it to frost
- off-palette priority colors
- a test harness that rendered sheets LTR

The redesign keeps product truth and the honey/sage/pomegranate meanings, and
replaces the structure and the glass:
- MODE: Operate. Material 3 governs structure; the brand is themed through it.
- STRUCTURE:
  - a medium top app bar that names the project
  - a drawer on phones and a glass navigation pane at 840px and above
  - full-bleed rows on phones, with a 760px measure on wide screens
  - a capture bar floating over the list end
  - an editor side sheet at 820px and above; below that, a modal bottom sheet
- GLASS: only where content passes beneath it, one pane per region, never
  nested. The panes are a 12% tint with blur 20 over a room lit by two
  lights: a moving honey lamp and a fixed cool room light. The pebble
  relief is removed.
- DISCIPLINE KEPT: the One Lamp Rule, the done stamp, Naskh for the project
  title only, 48px targets, and reduced motion.

DESIGN.md and `.impeccable/design.json` record the shipped system. The
contract below is the #47 record, superseded where it conflicts.


## Direction contract
THESIS: the day's tasks seen through the pressed, patterned glass of an
Iranian home's door at night: warm room light behind, cool night in front.
It refuses the category default of floating neon blobs behind generic
frosted cards.

OWN-WORLD:
- **Ground:** indigo night, `#0E1220`, deepening to `#0A0D18`.
- **Panes:** frosted honey-white at about 7.5% with a hairline light edge, and a
  faint pressed-pebble relief that calms under text.
- **Honey lamplight:** means only "now", that is today and the primary
  action.
- **Other colors:** sage for tomorrow, pomegranate for overdue only.
- **Type:** Naskh headings, Vazirmatn body, tabular figures.

STORY: open the app at night and see what matters now: the project or day
heading, its open count and time budget, the near tasks lit, the rest quiet.
Check one off: it is stamped «انجام شد», its glass clears, and it folds
away.

FIRST VIEWPORT (phone): a Naskh heading at the top inside the night ground,
under a navigation-only bar. One dominant glass pane holds the list. The
capture field sits at the bottom with the honey send button. On desktop the
sidebar is a quieter pane, and the editor opens beside the list.

FORM: candidate 7 of 7 (patterned privacy glass), seed key 3a5bd5db.

FINISH: unreviewed and undocumented is unfinished; this build ends with the
finish review, the verdict, DESIGN.md, and every shipping raster carrying its
provenance.
