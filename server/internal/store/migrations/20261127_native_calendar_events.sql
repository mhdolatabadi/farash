CREATE TABLE native_calendar_events (
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 200),
 start_at TIMESTAMPTZ NOT NULL,
 end_at TIMESTAMPTZ NOT NULL,
 time_zone TEXT NOT NULL,
 version BIGINT NOT NULL DEFAULT 1,
 deleted_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK (end_at > start_at AND end_at <= start_at + interval '7 days')
);
CREATE INDEX native_calendar_events_owner_range ON native_calendar_events(owner_id, start_at, end_at) WHERE deleted_at IS NULL;
CREATE TRIGGER native_calendar_events_updated BEFORE UPDATE ON native_calendar_events FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TABLE calendar_event_create_requests (
 owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 request_key TEXT NOT NULL,
 payload_hash BYTEA NOT NULL,
 response JSONB NOT NULL,
 PRIMARY KEY (owner_id, request_key)
);
