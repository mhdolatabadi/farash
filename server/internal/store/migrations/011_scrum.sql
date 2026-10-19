-- Project method is deliberately independent from future project membership.
ALTER TABLE projects ADD COLUMN method TEXT NOT NULL DEFAULT 'simple' CHECK (method IN ('simple','kanban','scrum'));
CREATE TABLE sprints (
 id TEXT PRIMARY KEY, owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 project_id TEXT NOT NULL, request_key TEXT NOT NULL, name TEXT NOT NULL CHECK(length(trim(name)) BETWEEN 1 AND 120),
 goal TEXT NOT NULL DEFAULT '' CHECK(length(goal)<=4000),
 starts_on DATE NOT NULL, ends_on DATE NOT NULL CHECK(ends_on>=starts_on AND ends_on<=starts_on+90),
 capacity INTEGER CHECK(capacity BETWEEN 0 AND 10000),
 state TEXT NOT NULL DEFAULT 'planned' CHECK(state IN ('planned','active','closed')),
 started_at TIMESTAMPTZ, closed_at TIMESTAMPTZ,
 committed_points INTEGER NOT NULL DEFAULT 0, committed_count INTEGER NOT NULL DEFAULT 0,
 review TEXT NOT NULL DEFAULT '' CHECK(length(review)<=20000), retro TEXT NOT NULL DEFAULT '' CHECK(length(retro)<=20000),
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(owner_id,project_id,id), UNIQUE(owner_id,project_id,request_key),
 FOREIGN KEY(owner_id,project_id) REFERENCES projects(owner_id,id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX one_active_sprint_per_project ON sprints(project_id) WHERE state='active';
CREATE TABLE scrum_items (
 task_id TEXT PRIMARY KEY REFERENCES tasks(id) ON DELETE CASCADE,
 owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
 sprint_id TEXT REFERENCES sprints(id) ON DELETE SET NULL,
 issue_type TEXT NOT NULL DEFAULT 'task' CHECK(issue_type IN ('task','story','bug','epic')),
 points INTEGER CHECK(points BETWEEN 0 AND 1000),
 acceptance TEXT NOT NULL DEFAULT '' CHECK(length(acceptance)<=20000),
 stage TEXT NOT NULL DEFAULT 'todo' CHECK(stage IN ('todo','doing'))
);
CREATE INDEX scrum_items_sprint ON scrum_items(sprint_id);
-- Intentional snapshots, not FKs to mutable tasks: deletion/movement/undo must
-- never erase or rewrite a closed sprint's measured history.
CREATE TABLE sprint_scope (
 sprint_id TEXT NOT NULL REFERENCES sprints(id) ON DELETE CASCADE,
 task_id TEXT NOT NULL, title TEXT NOT NULL, points INTEGER,
 completed BOOLEAN NOT NULL DEFAULT FALSE, removed_at TIMESTAMPTZ,
 PRIMARY KEY(sprint_id,task_id)
);
CREATE TABLE sprint_events (
 id BIGSERIAL PRIMARY KEY, sprint_id TEXT NOT NULL REFERENCES sprints(id) ON DELETE CASCADE,
 at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(), kind TEXT NOT NULL,
 scope_points INTEGER NOT NULL, remaining_points INTEGER NOT NULL,
 scope_count INTEGER NOT NULL, remaining_count INTEGER NOT NULL
);
CREATE INDEX sprint_events_sprint ON sprint_events(sprint_id,id);
CREATE FUNCTION record_sprint_event(sid TEXT, event_kind TEXT) RETURNS VOID LANGUAGE SQL AS $$
 INSERT INTO sprint_events(sprint_id,kind,scope_points,remaining_points,scope_count,remaining_count)
 SELECT sid,event_kind,COALESCE(sum(points),0),COALESCE(sum(points) FILTER(WHERE NOT completed),0),count(*),count(*) FILTER(WHERE NOT completed)
 FROM sprint_scope WHERE sprint_id=sid AND removed_at IS NULL;
$$;
CREATE FUNCTION scrum_task_history() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE sid TEXT; moved BOOLEAN;
BEGIN
 -- This lock serializes ordinary task changes against sprint closure as well.
 PERFORM id FROM projects WHERE id=OLD.project_id FOR UPDATE;
 moved := TG_OP='DELETE';
 IF TG_OP='UPDATE' THEN moved := NEW.deleted_at IS NOT NULL OR NEW.project_id<>OLD.project_id; END IF;
 FOR sid IN SELECT s.id FROM sprints s JOIN sprint_scope sc ON sc.sprint_id=s.id
   WHERE s.state='active' AND s.owner_id=OLD.owner_id AND sc.task_id=OLD.id AND sc.removed_at IS NULL LOOP
   IF moved THEN
     UPDATE sprint_scope SET removed_at=clock_timestamp() WHERE sprint_id=sid AND task_id=OLD.id;
   ELSE
     UPDATE sprint_scope SET completed=(NEW.completed_at IS NOT NULL),title=NEW.title WHERE sprint_id=sid AND task_id=OLD.id;
   END IF;
   PERFORM record_sprint_event(sid,CASE WHEN moved THEN 'removed' ELSE 'task_changed' END);
 END LOOP;
 IF moved THEN
   UPDATE scrum_items SET sprint_id=NULL,stage='todo' WHERE task_id=OLD.id;
 ELSIF TG_OP='UPDATE' AND OLD.completed_at IS NOT NULL AND NEW.completed_at IS NULL THEN
   UPDATE scrum_items SET stage='todo' WHERE task_id=OLD.id;
 END IF;
 RETURN NULL;
END;
$$;
CREATE TRIGGER scrum_task_history AFTER UPDATE OF completed_at,deleted_at,project_id,title OR DELETE ON tasks FOR EACH ROW EXECUTE FUNCTION scrum_task_history();
