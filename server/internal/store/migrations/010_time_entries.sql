CREATE TABLE time_entries (
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
 task_title TEXT NOT NULL,
 started_at TIMESTAMPTZ NOT NULL,
 ended_at TIMESTAMPTZ,
 planned_end TIMESTAMPTZ,
 source TEXT NOT NULL CHECK (source IN ('timer','focus','manual')),
 request_key TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK (ended_at IS NULL OR ended_at > started_at),
 CHECK (planned_end IS NULL OR planned_end > started_at),
 UNIQUE(owner_id, request_key)
);
CREATE UNIQUE INDEX one_running_time_entry ON time_entries(owner_id) WHERE ended_at IS NULL;
CREATE INDEX time_entries_owner_started ON time_entries(owner_id, started_at);
CREATE TRIGGER time_entries_updated BEFORE UPDATE ON time_entries FOR EACH ROW EXECUTE FUNCTION set_updated_at();
