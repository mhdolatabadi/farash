CREATE TABLE habits (
 id TEXT PRIMARY KEY,
 owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 200),
 question TEXT NOT NULL DEFAULT '',
 notes TEXT NOT NULL DEFAULT '',
 color SMALLINT NOT NULL DEFAULT 8 CHECK (color BETWEEN 0 AND 19),
 kind TEXT NOT NULL DEFAULT 'boolean' CHECK (kind IN ('boolean','numeric')),
 freq_num SMALLINT NOT NULL DEFAULT 1,
 freq_den SMALLINT NOT NULL DEFAULT 1,
 target_type TEXT NOT NULL DEFAULT 'at_least' CHECK (target_type IN ('at_least','at_most')),
 target_value DOUBLE PRECISION NOT NULL DEFAULT 0,
 unit TEXT NOT NULL DEFAULT '',
 sort_order INTEGER NOT NULL DEFAULT 0,
 archived_at TIMESTAMPTZ,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK (freq_num >= 1 AND freq_den >= 1 AND freq_den <= 365 AND freq_num <= freq_den),
 CHECK (target_value >= 0)
);
CREATE INDEX habits_owner_order ON habits(owner_id, sort_order);
CREATE TRIGGER habits_updated BEFORE UPDATE ON habits FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- One row per checked day. A day without a row is unknown, as in Loop.
CREATE TABLE habit_entries (
 habit_id TEXT NOT NULL REFERENCES habits(id) ON DELETE CASCADE,
 owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 day DATE NOT NULL,
 value DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (value >= 0),
 skip BOOLEAN NOT NULL DEFAULT false,
 updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 PRIMARY KEY (habit_id, day)
);
CREATE INDEX habit_entries_owner ON habit_entries(owner_id, habit_id, day);
