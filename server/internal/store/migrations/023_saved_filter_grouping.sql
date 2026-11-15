ALTER TABLE saved_filters
    ADD COLUMN IF NOT EXISTS group_by TEXT NOT NULL DEFAULT 'none'
    CHECK (group_by IN ('none', 'date', 'priority', 'project', 'label'));
