CREATE TABLE projects (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    parent_id TEXT,
    name TEXT NOT NULL,
    color TEXT NOT NULL DEFAULT '#7c3aed',
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    is_archived BOOLEAN NOT NULL DEFAULT FALSE,
    is_inbox BOOLEAN NOT NULL DEFAULT FALSE,
    kind TEXT NOT NULL DEFAULT 'project' CHECK (kind IN ('project', 'folder')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (length(trim(name)) > 0),
    CHECK (parent_id IS NULL OR parent_id <> id),
    UNIQUE (owner_id, id),
    FOREIGN KEY (owner_id, parent_id) REFERENCES projects (owner_id, id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX projects_one_inbox_per_owner
    ON projects (owner_id)
    WHERE is_inbox;

CREATE INDEX projects_owner_sort_idx
    ON projects (owner_id, is_archived, sort_order, created_at);

CREATE TRIGGER projects_set_updated_at
    BEFORE UPDATE ON projects
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();
