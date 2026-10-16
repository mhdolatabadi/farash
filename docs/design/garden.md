> Archived direction: superseded by the user-approved Persian weaving world. See `weaving.md` and root `DESIGN.md`. This file records the earlier botanical design only.

# Garden redesign — #64

Mode: Operate, with a game-like sanctuary as home.

The explicit choice was «فضای بازی‌گونه»: garden and visible growth lead; tasks orbit them. First viewport proves actual growth, then offers a next action. Desktop places the next tasks beside the garden; mobile stacks them below it. Garden, Tasks and Focus remain directly reachable.

Growth is tied to confirmed completion counts, not app opens or a timer's existence. Completing and undoing work updates the account's own score. No new backend reward currency is invented. The timer remains honest about its local-session lifecycle.

The calendar fix in #65 uses calendar dates, not 24-hour additions. During an autumn daylight-saving transition, adding durations to local midnight can produce duplicate date keys. Distinct civil dates prevent duplicate agenda heading keys. The week strip uses its supplied days so Today appears in the week view.

## Reference authority and evidence

Todoist (https://www.todoist.com/features) informed fast capture and clear task hierarchy; TickTick (https://ticktick.com/features) informed distinct task/planning/focus destinations; Pomofocus (https://pomofocus.io/) informed one legible timer and one primary action; Forest (https://forestapp.cc/) informed a consistent botanical world and emotionally legible growth. Official product pages were studied; Pomofocus and Forest were also inspected visually. No third-party artwork is bundled. The user selected the garden direction; the local concept helper ran degraded without catalog challengers. Implementation is code-led, preserving Flutter product behavior.

Widget captures use synthetic fixtures and verify layout, not an actual user's progress. Phone, desktop, dark-mode and 2× text widget evidence is distinct from native Android evidence. Android builds run in CI. The follow-up native emulator capture fixture is preparation for Android evidence; no completed native capture is claimed here. Hardware and accessibility-service validation remain open.
