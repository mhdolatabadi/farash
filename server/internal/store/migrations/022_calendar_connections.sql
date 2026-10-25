-- Provider credentials and OAuth attempts are encrypted by an application key;
-- this migration never stores plaintext bearer credentials or authorization codes.
CREATE TABLE calendar_owner_epochs (
 owner_id text PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 epoch bigint NOT NULL DEFAULT 0
);
CREATE TABLE calendar_oauth_attempts (
 id text PRIMARY KEY,
 owner_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 epoch bigint NOT NULL,
 client text NOT NULL CHECK (client IN ('web','android')),
 ticket_hash text UNIQUE,
 state_hash text UNIQUE,
 browser_hash text,
 verifier bytea NOT NULL,
 consent boolean NOT NULL DEFAULT false,
 expires_at timestamptz NOT NULL DEFAULT (now()+interval '10 minutes')
);
CREATE INDEX calendar_oauth_attempts_owner ON calendar_oauth_attempts(owner_id);
CREATE TABLE calendar_connections (
 id text PRIMARY KEY,
 owner_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 provider text NOT NULL CHECK(provider='google'),
 status text NOT NULL CHECK(status IN ('connected','reconnect_required')),
 credentials bytea NOT NULL,
 version bigint NOT NULL DEFAULT 1,
 UNIQUE(owner_id,provider)
);
CREATE TABLE connected_calendars (
 id text PRIMARY KEY,
 connection_id text NOT NULL REFERENCES calendar_connections(id) ON DELETE CASCADE,
 provider_id text NOT NULL,
 title text NOT NULL,
 time_zone text NOT NULL,
 selected boolean NOT NULL DEFAULT false,
 UNIQUE(connection_id,provider_id)
);
