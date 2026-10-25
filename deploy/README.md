# Deploy Farash

Farash runs on one Ubuntu server with Docker Compose: the Go API, PostgreSQL,
the Flutter web app behind nginx, and Caddy for automatic HTTPS.

## Production launch

1. Point `FARASH_DOMAIN` at the server and open ports `80` and `443`.
2. Clone the repository on the server, for example under `/home/apps/farash`.
3. On the server, create `deploy/.env` from `deploy/.env.example` and fill in
   the real domain, PostgreSQL password and JWT secret. Never commit `.env`.
4. Make sure the server can pull the GHCR images. If the packages are private,
   log in once on the server with a token that has `read:packages`.
5. Add these repository secrets in GitHub, matching the Nafir deploy setup:

   | Secret | Purpose |
   | --- | --- |
   | `DEPLOY_HOST` | Server IP or hostname |
   | `DEPLOY_USER` | SSH user that can run Docker |
   | `DEPLOY_PATH` | Repository path on the server, for example `/home/apps/farash` |
   | `DEPLOY_SSH_KEY` | Private key for that user |
   | `DEPLOY_KNOWN_HOSTS` | Server SSH host key entry |
   | `DEPLOY_PORT` | Optional SSH port; defaults to `22` |

6. Merge to `main`, or run **Images** and then **Deploy** manually from GitHub
   Actions. `Images` publishes immutable images:

   - `ghcr.io/mhdolatabadi/farash/api:<commit-sha>`
   - `ghcr.io/mhdolatabadi/farash/web:<commit-sha>`

7. `Deploy` SSHes to the server and runs:

   ```bash
   bash "$DEPLOY_PATH/deploy/deploy.sh" <commit-sha>
   ```

   The script fetches that commit, sets `FARASH_IMAGE_TAG`, pulls the images,
   runs `docker compose up -d --no-build --remove-orphans`, and checks:

   ```bash
   curl https://$FARASH_DOMAIN/api/v1/health
   ```

The API applies its database migrations on startup. PostgreSQL is reachable
only on Docker's internal network.

## Manual fallback

From the server repository checkout:

```bash
cd deploy
cp .env.example .env
# edit .env
docker compose up -d --build
```

Never commit deployment secrets or `.env`.

## Database backups and rollback

Every deployment starts only PostgreSQL first, then runs `bash deploy/backup.sh`
before the new API can apply migrations. This includes fresh installations and
existing database volumes whose previous container was removed. A stopped or
unreachable database and an invalid archive abort deployment. The PostgreSQL
major version remains 16; upgrading PostgreSQL itself requires a separate backup
and migration procedure before changing its image.

The default directory is `deploy/backups/`, with owner-only files and a SHA-256
sidecar for each custom-format dump. Override `FARASH_BACKUP_DIR` in the deployment
process to choose a different absolute directory. The script validates each dump
with `pg_restore --list` and never deletes old snapshots. Monitor disk space and
configure retention and encrypted off-server copies separately: a local snapshot
is not an off-server disaster-recovery policy.

Verify and restore to an isolated PostgreSQL 16 database before a production
recovery is needed:

```bash
sha256sum --check /absolute/path/to/snapshot.dump.sha256
pg_restore --exit-on-error --no-owner --dbname="$RESTORE_DATABASE_URL" /absolute/path/to/snapshot.dump
```

Production restore is a separate maintenance operation: stop writers and verify
the exact database and snapshot before replacing data. It can discard writes
after the snapshot. Code rollback normally retains additive tables/history;
never drop production data just to roll back application code.

## Signed Android releases

The **Android release** workflow runs on tags such as `v1.2.3`, or manual dispatch
with version `1.2.3`. It waits up to five minutes for successful **Quality checks**
on the exact source commit. If checks need longer, rerun release after they pass.
The workflow does not create tags or publish a store listing. A version tag publishes
verified APK/AAB downloads and checksums on a GitHub Release after uploading all
assets to a draft. Manual dispatch produces private Actions artifacts only and
never publishes a download page. Store rollout remains a separate explicit action.

Configure these repository secrets without committing their values:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Single-line Base64 of the production JKS/PKCS12 keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Production signing alias |
| `ANDROID_KEY_PASSWORD` | Private-key password |

Retain the same production key for updates to installed releases and keep an
independent secure backup of it. `FARASH_API_BASE_URL` is an optional repository
variable and defaults to `https://farash.mhdolatabadi.ir`.

Artifacts contain signed release APK and AAB files plus `SHA256SUMS`. Names include
the selected version and build number `100000 + workflow run number`, so separate
runs receive increasing codes. Re-running one workflow keeps its build code. The
resolver rejects malformed versions, a manual version that disagrees with its tag,
and version codes above 2100000000 (the Google Play limit). See the official
[Android versioning guidance](https://developer.android.com/studio/publish/versioning).
Missing signing configuration fails release tasks instead of silently using the
shared debug key. Ordinary debug CI remains available.

The workflow verifies the APK package, exact requested version name/build number,
non-debuggable flag and certificate against
the supplied production keystore, and verifies the AAB signature and certificate.
PR checks validate workflow syntax, signing preparation, debug compatibility and
a real database backup/restore. They do not prove production secrets exist or that
a signed release ran. Inspect the first signed artifacts and install the APK on
an Android device before closing #27.


### Publication and device rollout gates

A tag must refer to the exact commit whose Quality checks succeeded. Release
assets are not overwritten: a pre-existing release (including a draft from an
interrupted upload) stops publication. Inspect that draft before deliberately
removing it or use a new version tag; never replace a distributed build in place.
A successful release is downloadable from the repository's Releases page; the
90-day Actions copy is a build record, not the long-term download location.

Before distributing the first signed APK or submitting an AAB to Cafe Bazaar or
another store, record the actual results in #120:

- Install the signed release on an Android device; verify package/version and
  production API reachability. A debug CI APK is not this result.
- Upgrade from the previous signed release with the same key and a greater build
  number; verify login, task/history data, settings and offline reads survive.
  A downgrade rollback requires a new higher build number, not an older APK.
- Verify Persian RTL, large text/keyboard clearance, focus/time tracking while
  backgrounded, and calendar authorization return flow when that feature ships.
- Select the store account and stable product identity, prepare real current
  screenshots and the privacy/support URLs, and complete the store's data
  disclosures. Credentials and keystore backups stay outside the repository.
- Start with the selected store's limited rollout, monitor crash/login/network
  failures, then expand. Store approval is separate from GitHub publication.

The workflow's existence does not prove signing secrets are configured. No real
signed workflow run, device upgrade, or store submission was performed by the
release-readiness implementation. Those results must be recorded explicitly.
