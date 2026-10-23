CREATE TABLE saved_filters (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 80),
    query TEXT NOT NULL CHECK (length(query) <= 1000),
    color TEXT NOT NULL DEFAULT '#8B88A0',
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    sort TEXT NOT NULL DEFAULT 'due' CHECK (sort IN ('due', 'priority', 'title', 'project')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX saved_filters_owner_idx ON saved_filters (owner_id, is_favorite, created_at);
CREATE TRIGGER saved_filters_set_updated_at
    BEFORE UPDATE ON saved_filters
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
