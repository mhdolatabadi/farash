CREATE TABLE comments (
    id TEXT PRIMARY KEY,
    owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    project_id TEXT,
    task_id TEXT,
    body TEXT NOT NULL CHECK (length(body) <= 16000),
    request_key TEXT NOT NULL,
    request_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    deleted_at TIMESTAMPTZ,
    CHECK (num_nonnulls(project_id, task_id) = 1),
    CHECK (deleted_at IS NOT NULL OR length(trim(body)) > 0),
    FOREIGN KEY (owner_id, project_id) REFERENCES projects(owner_id,id) ON DELETE CASCADE,
    FOREIGN KEY (owner_id, task_id) REFERENCES tasks(owner_id,id) ON DELETE CASCADE,
    UNIQUE (owner_id, request_key)
);
CREATE INDEX comments_project_page ON comments(owner_id, project_id, created_at, id) WHERE project_id IS NOT NULL;
CREATE INDEX comments_task_page ON comments(owner_id, task_id, created_at, id) WHERE task_id IS NOT NULL;
