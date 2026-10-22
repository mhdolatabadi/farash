# Project collaboration foundation (#96)

This backend prerequisite for #22/#83 persists membership consent without widening existing task visibility. It is not a completed shared-project feature. No sharing controls are advertised in the client and no invitation email or other message is sent.

The owner remains `projects.owner_id`; members have editor/viewer roles. Regular non-Inbox projects only. Owners invite an existing account by email, recipients accept/decline in their authenticated invitation inbox, owners change member roles/remove members/revoke pending invitations, and members can leave. Owners cannot leave or be demoted through these APIs. Invitations expire after seven days. Membership mutations serialize on the project row. Acceptance/decline retries are safe; leaving/removal revokes the old accepted invitation, so it cannot regain access. No bearer invitation links exist yet.

API base `/api/v1/projects/{project}/collaboration`: GET member roster; POST invitations with `email,role`; DELETE invitations/{id}; POST invitations/{id}/accept or /decline; PATCH members/{userID} with role; DELETE members/{userID}; POST leave. GET `/api/v1/collaboration/invitations` lists only the caller's unexpired pending invites. Mutations return204. Roster contains IDs and roles, not account email addresses. Only owners see invitation records. Non-members and wrong recipients get404. Validation400, state conflicts409, mutation throttling429 (20/minute/account/process). Maximum100 members and200 invitation recipients per project bound storage; re-inviting an existing recipient reuses their record.

Archived projects retain roster reads and allow members to leave; invitation acceptance and owner mutations conflict. Expired/revoked invitations never authorize membership. Deleting the project/account cascades relevant records. Migration013 is additive; rollback leaves its tables in place and does not erase consent/history.

## Required before exposing shared projects

Audit and adapt the complete authorization boundary together: project listing/metadata, tasks/subtasks/reorder/completion/deletion, sections, project-bound label exposure, search/filters, Scrum scope/history, attachments/comments, time records and rewards. Keep private user labels, personal recorded time and account rewards private; do not impersonate the project owner for those services. Editor/viewer restrictions must be enforced in the store under the same project lock, not only hidden in UI. Add assignment membership constraints and revocation tests. Shared access must not leak parent folders or unrelated projects.

Current ordinary project/task/section/agile/time APIs still require their original owner. A successful membership acceptance here does not make those endpoints readable. Parent #22 remains open until this integration plus client invitation/project/assignment workflows and related notifications/comments are delivered.

## Validation

Store integration tests exercise privacy, consent, owner protections, role changes, accept/decline retry, leave/removal/revocation, expiration, archive and cascades. HTTP tests exercise every route's auth/privacy, validation, lifecycle and mutation throttling. Local execution was unavailable during preparation; PostgreSQL and API checks must pass in CI before integration. No physical-device or client sharing claim is made.
