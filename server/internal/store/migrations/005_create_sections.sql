CREATE TABLE sections (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    project_id TEXT NOT NULL,
    name TEXT NOT NULL CHECK (length(trim(name)) BETWEEN 1 AND 120),
    sort_order INTEGER NOT NULL DEFAULT 0,
    is_collapsed BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (owner_id, id),
    FOREIGN KEY (owner_id, project_id) REFERENCES projects (owner_id, id) ON DELETE CASCADE
);
CREATE INDEX sections_owner_project_sort ON sections (owner_id, project_id, sort_order, created_at);
CREATE TRIGGER sections_set_updated_at BEFORE UPDATE ON sections FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- A task sits in at most one section of its own project. Deleting a section
-- keeps its tasks in the project: only section_id is cleared.
ALTER TABLE tasks ADD COLUMN section_id TEXT;
ALTER TABLE tasks ADD CONSTRAINT tasks_section_fk
    FOREIGN KEY (owner_id, section_id) REFERENCES sections (owner_id, id) ON DELETE SET NULL (section_id);
CREATE INDEX tasks_owner_section ON tasks (owner_id, section_id) WHERE section_id IS NOT NULL;
