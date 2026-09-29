# AGENTS.md

This file defines the standing rules for every contributor and coding agent working on Farash.

## Product Identity And Scope

- The product name is **Farash** (فراش). Do not introduce other names in code, copy, package names, artifacts, infrastructure, or documentation.
- Farash is a self-hosted, cross-platform to-do and planning app inspired by Todoist and TickTick.
- The supported first clients are **Web/PWA and Android**. Do not add, restore, build, test, or maintain iOS-specific code or workflows unless the owner explicitly changes this rule.
- The Android application ID is `ir.mhdolatabadi.farash`.
- Keep Web and Android behavior consistent where platform capabilities allow it.
- User-facing copy is Persian-first and the primary layout direction is RTL. English support comes through settings.

## Issue-First Delivery

- Every independently deliverable change starts with a GitHub issue before implementation.
- Break broad requests into focused issues with a clear outcome and acceptance criteria.
- Use a dedicated branch and pull request for each issue or tightly related issue set. Reference and close the issue from the pull request.
- Do not mix unrelated cleanup or features into the same pull request.
- Keep the issue and pull request updated when scope, risks, or rollout requirements change.
- Follow the roadmap issue order unless the owner explicitly reprioritizes.

## UI And UX

- Farash should feel calm, fast, and serious enough for daily planning. Avoid noisy dashboards and marketing-style screens inside the app.
- Mobile layouts need generous breathing room, safe-area awareness, and touch targets of at least 48 logical pixels.
- Floating controls, bottom sheets, snackbars, notification prompts, browser chrome, and system insets must never cover the last task or a primary action.
- Persian, Arabic, and Latin task text must wrap or truncate gracefully without overflow.
- Desktop content should use a readable max width and must not stick to the viewport edges.
- Preserve accessibility semantics, visible focus, useful tooltips, and adequate contrast.
- Before making substantial UI changes, inspect and follow the relevant guidance stored under `.skill/`.

## Task And Planning Behavior

- Capture must stay fast: adding a task should be possible with one field and one clear action.
- Every account has one undeletable Inbox. Project/list, section, label, filter, and shared-object queries must be owner-scoped unless sharing explicitly grants access.
- Another user's private object must answer `404`, not `403`, to avoid leaking existence.
- Dates must support Jalali-first UX, Persian digits where appropriate, and predictable time-zone behavior.
- Recurring tasks, reminders, notifications, and calendar/time-blocking changes must define exact edge-case behavior before implementation.
- Completion, deletion, archival, and history should be auditable and reversible where the product model allows it.
- Offline behavior must preserve user intent and reconcile safely once sync exists. The server remains the source of truth.

## Backend, Storage, And Abuse Protection

- Keep all user data private by default and scope every query by authenticated user ID.
- Store passwords only as bcrypt hashes. Never log passwords, tokens, signing material, private URLs, or sensitive task content.
- JWT settings, token TTLs, CORS origins, database URLs, and deployment secrets must come from configuration.
- Validate request bodies with explicit errors and stable machine-readable error codes.
- Rate-limit abuse-sensitive endpoints such as register, login, quick-add parsing, imports, and attachment uploads.
- Database migrations must be small, ordered, idempotent through the migration table, and safe for existing data.
- Attachment support, when added, must keep PostgreSQL records and object storage consistent during failures and deletion.

## Testing And Quality Gates

- Add or update tests for every behavior change and regression fix.
- At minimum, run formatting, static analysis, unit/widget tests, the web release build, and the Android build checks relevant to the change.
- API changes require tests for validation, authorization, ownership, rate limits, and failure responses.
- Mobile UI changes must include a narrow-screen regression check and must verify that controls do not obscure content.
- Do not merge while required CI checks are failing.
- If a local environment lacks Android SDK, Docker, PostgreSQL, Flutter, or another required tool, state exactly which checks could not be run and rely on CI for the missing gate.

## Deployment And Releases

- Production deployment happens through repository workflows after CI succeeds; avoid undocumented manual server mutations.
- Keep secrets in GitHub Actions secrets or the server environment. Never commit them.
- Validate Docker Compose and Caddy changes before deployment and preserve any documented external network contracts.
- Android releases must be signed **release** builds, never debug/test APKs.
- Release workflows must publish installable APK and store-ready AAB artifacts with an unambiguous version.
- Sideloaded APKs may still trigger Android's unknown-source confirmation; do not confuse that OS warning with a debug build.
- Cafe Bazaar and other stores are separate distribution targets and require an explicit issue and rollout plan.

## Safe Collaboration

- Preserve unrelated user changes and the current repository state.
- Prefer small, reversible changes and migrations.
- Diagnose production incidents with read-only checks first.
- Confirm exact destructive targets before deleting database rows, object-storage prefixes, Docker data, or user content.
- Document operational commands and rollback notes in the relevant issue or pull request.
