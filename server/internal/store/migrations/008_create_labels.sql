-- Labels are the owner's own tags, shared across their projects. A label's
-- name is unique per owner regardless of case.
CREATE TABLE labels (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 60),
    color TEXT NOT NULL DEFAULT '#8B88A0',
    is_favorite BOOLEAN NOT NULL DEFAULT FALSE,
    sort_order INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (owner_id, id)
);
CREATE UNIQUE INDEX labels_owner_name ON labels (owner_id, lower(name));
CREATE TRIGGER labels_set_updated_at BEFORE UPDATE ON labels FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Which labels a task carries. Deleting a label or a task drops the link.
CREATE TABLE task_labels (
    owner_id TEXT NOT NULL,
    task_id TEXT NOT NULL,
    label_id TEXT NOT NULL,
    PRIMARY KEY (task_id, label_id),
    FOREIGN KEY (owner_id, task_id) REFERENCES tasks (owner_id, id) ON DELETE CASCADE,
    FOREIGN KEY (owner_id, label_id) REFERENCES labels (owner_id, id) ON DELETE CASCADE
);
CREATE INDEX task_labels_owner_label ON task_labels (owner_id, label_id);
