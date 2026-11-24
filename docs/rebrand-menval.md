# Menval rebrand — compatibility and rollout

The product formerly known as **Farash (فراش)** is now **Menval (منوال)**. The Web/PWA and Android user-facing title must show the new brand.

## Stable legacy technical identifiers
- Android applicationId and Kotlin namespace `ir.mhdolatabadi.farash`: deliberately unchanged to preserve upgrades, app data and sessions.
- Old persistent storage keys (if they include `farash`): do not rename without a data migration.
- Production domain, OAuth callback URLs, repository `mhdolatabadi/farash`, Go module, GHCR image paths, Docker networks, containers, volume names, DB credentials, deployment paths, and `FARASH_*` environment variable names are deployed identifiers. Keep them until coordinated migration.
- Do not change signing identity or replace the existing app with a new Android application ID.

## Validation
- Check Web tab title, PWA install name, Android launcher label and in-app branding.
- Run Flutter analyze and tests, server Go tests, Android release checks.
- Verify an Android upgrade preserves login, existing content and offline preferences; verify live production deploy uses existing images and secrets.
- Repo rename, domain move, package/containers renames, and asset redesign require separate migrations and smoke tests.

The current icon artwork remains intentionally unchanged; this step changes naming, not visual identity.
