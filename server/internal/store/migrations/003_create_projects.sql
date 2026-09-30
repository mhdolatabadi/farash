CREATE TABLE projects (
    id text PRIMARY KEY,
    owner_id text NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    parent_id text REFERENCES projects (id) ON DELETE CASCADE,
    name text NOT NULL,
    color text NOT NULL DEFAULT 'charcoal',
    is_inbox boolean NOT NULL DEFAULT false,
    is_favorite boolean NOT NULL DEFAULT false,
    is_archived boolean NOT NULL DEFAULT false,
    child_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT projects_name_length CHECK (char_length(name) BETWEEN 1 AND 120),
    CONSTRAINT projects_inbox_is_top_level CHECK (NOT is_inbox OR (parent_id IS NULL AND NOT is_archived))
);

-- Every account has exactly one Inbox.
CREATE UNIQUE INDEX projects_one_inbox_per_owner ON projects (owner_id) WHERE is_inbox;
CREATE INDEX projects_owner_order ON projects (owner_id, parent_id, child_order);

CREATE TRIGGER projects_set_updated_at
BEFORE UPDATE ON projects
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Accounts created before projects existed get their Inbox now.
INSERT INTO projects (id, owner_id, name, is_inbox)
SELECT md5(random()::text || clock_timestamp()::text || users.id), users.id, 'Inbox', true
FROM users;
