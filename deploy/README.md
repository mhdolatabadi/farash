# Deploy Farash

Farash runs on one Ubuntu server with Docker Compose: the Go API, PostgreSQL,
the Flutter web app behind nginx, and Caddy for automatic HTTPS.

## Production launch

1. Point `FARASH_DOMAIN` at the server and open ports `80` and `443`.
2. Create the deploy directory on the server, for example `/home/apps/farash`.
3. Add these repository secrets in GitHub:

   | Secret | Purpose |
   | --- | --- |
   | `FARASH_SSH_HOST` | Server IP or hostname |
   | `FARASH_SSH_USER` | SSH user that can run Docker |
   | `FARASH_SSH_KEY` | Private key for that user |
   | `FARASH_SSH_PORT` | SSH port, usually `22` |
   | `FARASH_DEPLOY_PATH` | Server path, for example `/home/apps/farash` |
   | `FARASH_DOMAIN` | Public domain, for example `farash.mhdolatabadi.ir` |
   | `FARASH_POSTGRES_PASSWORD` | Long random PostgreSQL password |
   | `FARASH_AUTH_JWT_SECRET` | Long random token secret |
   | `FARASH_GHCR_TOKEN` | GitHub PAT with `read:packages` for GHCR pulls |

4. Optional repository variable:

   | Variable | Default | Purpose |
   | --- | --- | --- |
   | `FARASH_AUTH_TOKEN_TTL_HOURS` | `24` | Access-token lifetime |

5. Merge the production PR to `main`, or run **Deploy web** manually from GitHub
   Actions. The workflow builds and pushes these images to GHCR:

   - `ghcr.io/mhdolatabadi/farash/api:<commit-sha>`
   - `ghcr.io/mhdolatabadi/farash/web:<commit-sha>`

6. The workflow copies this directory to the server, writes `.env` from secrets,
   pulls the images, runs `docker compose up -d --remove-orphans`, and checks:

   ```bash
   curl https://$FARASH_DOMAIN/api/v1/health
   ```

The API applies its database migrations on startup. PostgreSQL is reachable
only on Docker's internal network.

## Manual fallback

If the workflow is unavailable, copy this directory to the server, create `.env`
from `.env.example`, then run:

```bash
docker compose up -d --build
```

Never commit deployment secrets or `.env`.
