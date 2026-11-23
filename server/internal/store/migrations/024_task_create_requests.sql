-- Offline command foundation: remember successful task creates even if the
-- underlying task is later soft/hard deleted. Never replay a POST into a new row.
CREATE TABLE task_create_requests (
    owner_id text NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    request_key text NOT NULL CHECK (length(request_key) BETWEEN 16 AND 128),
    payload_hash bytea NOT NULL CHECK (octet_length(payload_hash) = 32),
    response jsonb NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(owner_id, request_key)
);
