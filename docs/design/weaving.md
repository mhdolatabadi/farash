# Weaving redesign

## Selected world

The user explicitly rejected Forest similarity, proposed a Persian woven rug and approved that direction. They then required the same high artistic quality throughout the UI. This supersedes the botanical direction in the archival `garden.md`. Todoist and TickTick remain utility references for clear capture and hierarchy; Pomofocus remains a reference for one legible timer. Their visual identities are not the selected world.

The home is an atelier: an original transparent loom illustration provides atmosphere; a labelled procedural rug card proves measured progress. Wool cream, terracotta, turquoise and midnight ink extend through the shared theme, including menus, cards and fields. The illustration is decorative and static; it never purports to show actual rows. Artwork should retain its intended transparent silhouette and detail without substituting a generic botanical scene.

## Progress contract

`WeaveProgress` derives everything from server-confirmed completed count. Each completed task adds one row; 50 rows complete one rug. Current rows are `completed % 50`; collection count is `completed ~/ 50`. At 50, the collection contains one rug and the current rug starts at zero. Undo reverses this deterministically, including crossing a collection boundary. Collection patterns cycle through three authored palettes by index. The available data cannot identify historical project contributions, project-specific threads or project colors; these must not be claimed.

The collection is a derived visualization, not a separately persisted reward inventory. Account level and XP remain API values. Missing progress shows an honest retry/unavailable state. Focus is local, preserves its running session across navigation, and does not create rug rows or XP. Starting focus for another task while a session runs explains that the existing session must first be paused.

## Layout and lifecycle

Weaving, Tasks and Focus are directly reachable. Phones stack the atelier and next actions; wide content places them beside each other. Existing start preferences remain respected, and the old persisted `garden` value migrates to `weaving`. Task completion, undo, project navigation and safe-area capture remain functional requirements.

## Verification scope

Widget captures use synthetic fixtures and verify layout, not an actual user's progress. Current CI and visual captures are pending; this document does not claim native capture completion or visual sign-off. Android build results, widget evidence, native emulator evidence, hardware performance and accessibility-service validation are distinct checks. The design system records the current implementation; the user's demand for high artistic quality across every surface remains a review criterion, not a claim that every surface has already passed visual review.
