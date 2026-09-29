-- Shared by every table with an updated_at column; offline sync (issue #21)
-- relies on it to find what changed.
CREATE FUNCTION set_updated_at() RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
