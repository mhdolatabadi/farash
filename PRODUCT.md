# Menval
<!-- impeccable:product-schema 1 -->

## Platform
Android and Web/PWA; iOS is out of scope.

## Product Purpose
Self-hosted, private, Persian-first task and planning app with projects, quick capture, calendar, focus, habits and time tracking.

## Capabilities and Constraints
Flutter client, Go API, PostgreSQL. Preserve owner-scoped accounts, projects, tasks, sections, priorities, completion and undo, calendar and project navigation. Roadmap features cannot appear as live controls before implementation. The redesign changes **visual presentation**, not product truth or backend contracts.

## Brand Commitments
منوال / Menval, Persian RTL, bundled Vazirmatn and clear Persian numerals. The owner explicitly requested a ground-up visual redesign on 2026-11-25; the previous light-teal/dark-lime neumorphic UI is no longer the approved direction. The current implementation candidate, **Menval Ledger**, is defined in DESIGN.md and must be judged from real light/dark Android and web captures. Preserve fast task capture, accessibility and sane information density.

## Migration Boundary
Android application ID `ir.mhdolatabadi.farash`, persisted storage keys, OAuth and deployment identifiers stay unchanged for compatibility. See `docs/rebrand-menval.md`.

## Product Principles
Fast one-field task entry; user data private by default; reversible completion/deletion; legible mixed-language task content; Web/Android parity; no invented statistics or inaccessible controls. Real hardware performance and accessibility-service validation remain separate release checks.
