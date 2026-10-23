> Archived: superseded by the calm Material 3 redesign (#116). See root `DESIGN.md`. The weaving code and artwork were removed.

# Weaving redesign

## Selected world

The user explicitly rejected Forest similarity, proposed a Persian woven rug and approved that direction. They then required the same high artistic quality throughout the UI. This supersedes the botanical direction in the archival `garden.md`. Todoist and TickTick remain utility references for clear capture and hierarchy; Pomofocus remains a reference for one legible timer. Their visual identities are not the selected world.

The home is an atelier: an original transparent loom illustration provides atmosphere; a labelled authored-rug reveal card proves measured progress. Wool cream, terracotta, turquoise and midnight ink extend through the shared theme, including menus, cards and fields. The illustration is decorative and static; it never purports to show actual rows. Artwork should retain its intended transparent silhouette and detail without substituting a generic botanical scene.

## Direction contract

**THESIS:** Daily work becomes a Persian textile; the whole application owns an atelier identity rather than an illustration above default utility chrome.

**OWN-WORLD:** Wool-cream containers, terracotta actions, turquoise accents, navy ink, nested woven diamonds, warm outlined paper surfaces and restrained lift remain recognizable without content.

**STORY:** See real accumulated effort, understand the next row, then complete a task or enter focused work. Undo must visibly unwind the same progress.

**FIRST VIEWPORT:** A bold Persian heading and level precede a 250-high loom (320 above 650 content width), thread ornament, labelled row card and next actions. Wide layout places scene and actions at 6:4; phone stacks them. Primary task/focus actions belong beside their relevant content. Signature interaction: exact bottom-up row reveal over warp (320 ms; reduced-motion instant), followed by a collected rug at each 50 confirmations.

**FORM:** Code-led, user-pinned weaving atelier. Prior ordered-form position and workshop seed are unavailable; none is invented. The selected form is carried by this contract rather than a new comp choice.

**FINISH:** unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Progress contract

`WeaveProgress` derives everything from server-confirmed completed count. Each completed task adds one row; 50 rows complete one rug. Current rows are `completed % 50`; collection count is `completed ~/ 50`. At 50, the collection contains one rug and the current rug starts at zero. Undo reverses this deterministically, including crossing a collection boundary. The current and collected rugs repeat one authored image, `assets/weaving/rug.png`; no distinct collection palette variants are implemented. `RugPattern` clips the exact revealed fraction from the bottom over a pale drawn warp and animates the change over 320 ms, instantly with reduced motion. The available data cannot identify historical project contributions, project-specific threads or project colors; these must not be claimed.

The collection is a derived visualization, not a separately persisted reward inventory. Account level and XP remain API values. Missing progress shows an honest retry/unavailable state. Focus is local, preserves its running session across navigation, and does not create rug rows or XP. Starting focus for another task while a session runs explains that the existing session must first be paused.

## Layout and lifecycle

Weaving, Tasks and Focus are directly reachable. Phones stack the atelier and next actions; wide content places them beside each other. Existing start preferences remain respected, and the old persisted `garden` value migrates to `weaving`. Task completion, undo, project navigation and safe-area capture remain functional requirements.

## Shared finish language

`WeaveMark` is the house diamond in navigation and account branding; `ThreadRule` repeats it between fine rules. `AtelierPanel` supplies warm outlined surfaces with restrained ambient lift. Task rows, capture, toolbar badges, selected sidebar items, chips and framed focus timer carry that same world. One collected rug gets a large presentation; multiple rugs use a lazy grid. Artwork provenance is in `assets/weaving/provenance.md`.

## Verification scope

Widget captures use synthetic fixtures and verify layout, not an actual user's progress. Source checks and widget tests cover the implemented behavior; run-specific results and captured UI artifacts are recorded in PR #74 and CI run 38907614454. Android build results, widget evidence, native emulator evidence, hardware performance and accessibility-service validation are distinct checks. The design system records the current implementation; the user's demand for high artistic quality across every surface remains a review criterion, not a substitute for the separate finish-review verdict.
