# Deploy Farash

Farash runs on one Ubuntu server with Docker Compose: the Go API, PostgreSQL,
the Flutter web app behind nginx, and Caddy for automatic HTTPS.

1. Point a DNS record (for example `todo.example.com`) at the server and open
   ports 80 and 443.
2. Copy this directory to the server, then create `.env` from `.env.example`
   and fill in every value. Never commit `.env`.
3. Build and start the stack:

   ```bash
   docker compose up -d --build
   ```

4. Open `https://todo.example.com/api/v1/health`; it answers
   `{"status":"ok"}` once the API reaches PostgreSQL.

The API applies its database migrations on startup. PostgreSQL is reachable
only on Docker's internal network. Image publishing, the deploy workflow and
backups are tracked in issue #27.
