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
