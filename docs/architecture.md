# Architecture

Farash is a self-hosted to-do and planning app with the same shape as
[Nafir](https://github.com/mhdolatabadi/nafir).

## Components

- **Flutter** renders the UI on Android and the web (PWA). It is Persian first:
  right-to-left layout, the bundled Vazirmatn font and, from issue #8, the
  Jalali calendar.
- **Go API** (`server/`) authenticates users and owns every read and write.
- **PostgreSQL** stores users, projects, sections, tasks, labels and the rest.
  Migrations are embedded in the API and applied in file-name order on
  startup, under an advisory lock.
- **Caddy** terminates HTTPS and serves the web app and the API under `/api/`.
- **Docker Compose** runs the server stack.

## Access control

PostgreSQL has no row-level policies; the Go API is the boundary. Every query
takes the authenticated user's ID from the access token and filters on it.
Another user's object answers `404 not_found`, the same as one that does not
exist, so IDs cannot be probed.

## Errors

Errors are JSON: `{"error": "<code>"}` with a machine-readable code such as
`not_found`, `invalid_request` or `email_taken`. The app maps codes to Persian
messages.

## Roadmap

Features are tracked as sub-issues of issue #1 and delivered in order.
