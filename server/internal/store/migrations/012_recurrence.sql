-- Each occurrence remains an ordinary task; its successor is a new task.
CREATE TABLE task_recurrences (
    task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,
    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    schedule JSONB NOT NULL,
    emitted INTEGER NOT NULL DEFAULT 1 CHECK (emitted > 0),
    next_task_id TEXT REFERENCES tasks(id) ON DELETE SET NULL,
    next_version TIMESTAMPTZ,
    advanced_at TIMESTAMPTZ,
    skipped BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX task_recurrences_owner ON task_recurrences(owner_id);
CREATE TABLE recurrence_events (
    id BIGSERIAL PRIMARY KEY,
    task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    kind TEXT NOT NULL CHECK (kind IN ('complete','skip','undo')),
    due JSONB,
    successor_id TEXT,
    at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);
CREATE INDEX recurrence_events_owner_task ON recurrence_events(owner_id, task_id, id);
