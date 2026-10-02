-- Due dates: an all-day date, or a moment (stored in UTC) with the IANA time
-- zone it was planned in; due_date is then that moment's local date. A
-- deadline is a separate date. A duration needs a timed due.
ALTER TABLE tasks ADD COLUMN due_date DATE;
ALTER TABLE tasks ADD COLUMN due_at TIMESTAMPTZ;
ALTER TABLE tasks ADD COLUMN due_timezone TEXT;
ALTER TABLE tasks ADD COLUMN deadline DATE;
ALTER TABLE tasks ADD COLUMN duration_minutes INTEGER;
ALTER TABLE tasks ADD CONSTRAINT tasks_due_time_has_zone CHECK ((due_at IS NULL) = (due_timezone IS NULL));
ALTER TABLE tasks ADD CONSTRAINT tasks_due_time_has_date CHECK (due_at IS NULL OR due_date IS NOT NULL);
ALTER TABLE tasks ADD CONSTRAINT tasks_duration_needs_time CHECK (duration_minutes IS NULL OR (due_at IS NOT NULL AND duration_minutes BETWEEN 1 AND 1440));
CREATE INDEX tasks_owner_due ON tasks (owner_id, due_date) WHERE deleted_at IS NULL AND due_date IS NOT NULL;
