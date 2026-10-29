-- A habit reminds at most once a day: a local minute of the day on the
-- chosen weekdays (bit 0 Monday ... bit 6 Sunday). No minute, no reminder.
ALTER TABLE habits
 ADD COLUMN IF NOT EXISTS reminder_minute SMALLINT CHECK (reminder_minute BETWEEN 0 AND 1439),
 ADD COLUMN IF NOT EXISTS reminder_days SMALLINT NOT NULL DEFAULT 127 CHECK (reminder_days BETWEEN 1 AND 127);
