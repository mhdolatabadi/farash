ALTER TABLE users ADD COLUMN weekly_active_days INTEGER NOT NULL DEFAULT 3 CHECK (weekly_active_days BETWEEN 1 AND 7);
CREATE INDEX tasks_owner_completion ON tasks(owner_id, completed_at) WHERE completed_at IS NOT NULL AND deleted_at IS NULL;
