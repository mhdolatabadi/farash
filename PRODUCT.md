# Menval
<!-- impeccable:product-schema 1 -->

## Platform
android

## Product Purpose
Self-hosted task and planning app, Persian-first, for daily capture and project
organization. Web/PWA and Android are supported; iOS is out of scope.

## Capabilities and Constraints
Flutter client, Go API, PostgreSQL. Preserve owner-scoped accounts/projects/tasks,
sections, priorities, completion, undo and project navigation. Roadmap features
must not appear as working controls before implementation.

## Brand Commitments
منوال / Menval, Persian RTL, bundled Vazirmatn. The owner approved an ivory and
charcoal tactile workspace: raised compact rows in inset wells, shared controls,
compact active-inset navigation, and a desktop sidebar/master-detail composition.
Brand is top right and search top left. Capture stays inside the page. Native
calendar events are independent of tasks. See DESIGN.md for the current contract.

## Migration boundary
The Android application ID, persisted storage keys and deployment identifiers retain the legacy `farash` spelling for compatibility. See `docs/rebrand-menval.md`.

## Product Principles
Fast one-field capture; private by default; reversible completion/deletion;
legible task content; Web and Android parity. Actual hardware performance and
accessibility-service validation remain open checks.
