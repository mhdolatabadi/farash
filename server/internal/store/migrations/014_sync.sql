-- A current-state feed, not a duplicate edit history. Owner-local revisions are
-- allocated under a transactional row lock, so a cursor cannot skip a late
-- commit that reserved a global sequence number earlier.
CREATE TABLE sync_versions (
 owner_id TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
 revision BIGINT NOT NULL CHECK (revision > 0)
);
CREATE TABLE sync_changes (
 owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 entity TEXT NOT NULL,
 entity_id TEXT NOT NULL,
 revision BIGINT NOT NULL,
 operation TEXT NOT NULL CHECK (operation IN ('upsert','delete')),
 data JSONB,
 PRIMARY KEY(owner_id,entity,entity_id),
 UNIQUE(owner_id,revision),
 CHECK ((operation='delete' AND data IS NULL) OR (operation='upsert' AND data IS NOT NULL))
);
CREATE FUNCTION sync_record(s_owner TEXT, s_entity TEXT, s_id TEXT, s_operation TEXT, s_data JSONB)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE s_revision BIGINT;
BEGIN
 -- Cascading account deletion must remove, rather than recreate, sync state.
 IF NOT EXISTS (SELECT 1 FROM users WHERE id=s_owner) THEN RETURN; END IF;
 INSERT INTO sync_versions(owner_id,revision) VALUES(s_owner,1)
 ON CONFLICT(owner_id) DO UPDATE SET revision=sync_versions.revision+1
 RETURNING revision INTO s_revision;
 INSERT INTO sync_changes(owner_id,entity,entity_id,revision,operation,data)
 VALUES(s_owner,s_entity,s_id,s_revision,s_operation,s_data)
 ON CONFLICT(owner_id,entity,entity_id) DO UPDATE
 SET revision=EXCLUDED.revision,operation=EXCLUDED.operation,data=EXCLUDED.data;
END;
$$;
CREATE FUNCTION sync_capture() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE value JSONB; row_id TEXT;
BEGIN
 IF TG_OP='DELETE' THEN value:=to_jsonb(OLD); ELSE value:=to_jsonb(NEW); END IF;
 IF TG_OP='UPDATE' AND OLD IS NOT DISTINCT FROM NEW THEN RETURN NULL; END IF;
 IF TG_TABLE_NAME='task_labels' THEN
   row_id:=jsonb_build_array(value->>'task_id',value->>'label_id')::text;
 ELSE row_id:=value->>'id'; END IF;
 PERFORM sync_record(value->>'owner_id',TG_TABLE_NAME,row_id,
   CASE WHEN TG_OP='DELETE' THEN 'delete' ELSE 'upsert' END,
   CASE WHEN TG_OP='DELETE' THEN NULL ELSE value-'owner_id'-'request_key' END);
 RETURN NULL;
END;
$$;
CREATE TRIGGER sync_projects AFTER INSERT OR UPDATE OR DELETE ON projects FOR EACH ROW EXECUTE FUNCTION sync_capture();
CREATE TRIGGER sync_sections AFTER INSERT OR UPDATE OR DELETE ON sections FOR EACH ROW EXECUTE FUNCTION sync_capture();
CREATE TRIGGER sync_tasks AFTER INSERT OR UPDATE OR DELETE ON tasks FOR EACH ROW EXECUTE FUNCTION sync_capture();
CREATE TRIGGER sync_labels AFTER INSERT OR UPDATE OR DELETE ON labels FOR EACH ROW EXECUTE FUNCTION sync_capture();
CREATE TRIGGER sync_task_labels AFTER INSERT OR UPDATE OR DELETE ON task_labels FOR EACH ROW EXECUTE FUNCTION sync_capture();
CREATE TRIGGER sync_time_entries AFTER INSERT OR UPDATE OR DELETE ON time_entries FOR EACH ROW EXECUTE FUNCTION sync_capture();

-- Existing accounts bootstrap through the same paginated feed. Migration runs
-- transactionally, so no client can observe a partially seeded feed.
SELECT sync_record(owner_id,'projects',id,'upsert',to_jsonb(p)-'owner_id') FROM projects p ORDER BY owner_id,id;
SELECT sync_record(owner_id,'sections',id,'upsert',to_jsonb(s)-'owner_id') FROM sections s ORDER BY owner_id,id;
SELECT sync_record(owner_id,'tasks',id,'upsert',to_jsonb(t)-'owner_id') FROM tasks t ORDER BY owner_id,id;
SELECT sync_record(owner_id,'labels',id,'upsert',to_jsonb(l)-'owner_id') FROM labels l ORDER BY owner_id,id;
SELECT sync_record(owner_id,'task_labels',jsonb_build_array(task_id,label_id)::text,'upsert',to_jsonb(t)-'owner_id') FROM task_labels t ORDER BY owner_id,task_id,label_id;
SELECT sync_record(owner_id,'time_entries',id,'upsert',to_jsonb(e)-'owner_id'-'request_key') FROM time_entries e ORDER BY owner_id,id;
