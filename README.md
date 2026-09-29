# Farash

فراش — a self-hosted, cross-platform to-do and planning app in the spirit of
Todoist and TickTick: projects, sections, subtasks, due dates in the Jalali
calendar, recurring tasks, labels, filters, reminders, board and calendar
views, an Eisenhower matrix, Pomodoro and habits. The roadmap lives in
issue #1; every feature has its own issue.

## Stack

- Flutter client for Android and Web/PWA, Persian first (RTL)
- Go HTTP API
- PostgreSQL
- Caddy for automatic HTTPS
- Docker Compose for Ubuntu deployment

See [docs/architecture.md](docs/architecture.md).

## Run the API locally

The API needs PostgreSQL. It applies its database migrations on startup.

```bash
docker run -d --name farash-db -p 5432:5432 \
  -e POSTGRES_USER=farash -e POSTGRES_PASSWORD=farash -e POSTGRES_DB=farash postgres:16-alpine
cd server
export DATABASE_URL='postgres://farash:farash@localhost:5432/farash?sslmode=disable'
TEST_DATABASE_URL="$DATABASE_URL" go test -p 1 ./...
go run ./cmd/api
```

Then open `http://localhost:8080/api/v1/health`. The store tests drop and
recreate the schema in `TEST_DATABASE_URL`, so point it at a disposable
database. `WEB_ORIGIN` allows one web origin to call the API cross-origin, and
`PORT` (default `8080`) sets the listening port.

| Endpoint | Purpose |
| --- | --- |
| `GET /api/v1/health` | `{"status":"ok"}` when the API reaches PostgreSQL, `503` otherwise |

## Run the Flutter app

Start the Go API, then run Flutter with its public base URL:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

`10.0.2.2` points to the host machine from the Android emulator. The web build
falls back to its own origin, so it works behind the same domain as the API.
The app checks `/api/v1/health` on startup and offers a retry when the server
is unavailable.

Every push to `main` builds a debug Android APK: download the
`farash-android-debug` artifact from the **Quality checks** run. The Android
application ID is `ir.mhdolatabadi.farash`. The APK talks to
`https://farash.mhdolatabadi.ir`; set the repository variable
`FARASH_API_BASE_URL` to point it elsewhere.

The app icon is a white check on teal. To change it, edit
`web/icons/icon.svg` and run `NODE_PATH=$(npm root -g) node tool/render_icons.js`
(needs Node and Playwright) to regenerate the Android, web and loading-screen
PNGs.

## Deploy

See [deploy/README.md](deploy/README.md). Do not commit deployment secrets or `.env`.
