-- Subtasks: a task may hang under another task of the same owner. The
-- subtree shares its root's project and section; the store keeps that
-- invariant and refuses cycles and trees deeper than five levels.
ALTER TABLE tasks ADD CONSTRAINT tasks_owner_id_id_key UNIQUE (owner_id, id);
ALTER TABLE tasks ADD COLUMN parent_id TEXT;
ALTER TABLE tasks ADD CONSTRAINT tasks_parent_fk FOREIGN KEY (owner_id, parent_id) REFERENCES tasks (owner_id, id) ON DELETE CASCADE;
ALTER TABLE tasks ADD CONSTRAINT tasks_parent_not_self CHECK (parent_id IS NULL OR parent_id <> id);
CREATE INDEX tasks_owner_parent ON tasks (owner_id, parent_id) WHERE parent_id IS NOT NULL;
