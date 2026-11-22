# Retina execution contract for Farash

This document adapts the Retina ecosystem's **agent orchestration standards** to Farash. Retina is the overall multi-layer agent ecosystem, not a single task runner. This is an execution contract, **not evidence that agents are running**.

## Runtime and authority

- **Execution:** ChatGPT performs repository analysis, scoped edits, PR creation and CI diagnosis through connected tools. No OpenCode or OpenRouter dependency is required. Tool access is not evidence of autonomous background workers or parallel ChatGPT agents.
- **Control plane:** GitHub issues, branches, PRs and Actions provide durable checkpoints. Record work item, execution lane, issue, branch, head SHA, attempts, check results, artifact references, approvals and terminal state. Do not claim an independent orchestrator exists until one is implemented. Never infer completion from a narrative.
- **Token observability only (v1):** record usage by Retina / orchestrator / issue / agent / stage / model only where provider telemetry is actually available. ChatGPT token usage may not be exposed by connected tools; mark unavailable, never invent measurements or optimize models automatically.
- **GitHub:** Farash's existing issue/PR/Actions delivery system. Do not claim Jira or Gerrit integration exists here. If the deployment provides Jira and Gerrit, map work items to Jira and use the two-stage Gerrit review process; otherwise GitHub issues and PR reviews are the explicit fallback.
- **No unauthorized execution:** do not claim background ChatGPT workers, GitHub Coding Agents or any parallel agents were launched without a real supported invocation and a durable run identifier. Lanes are coordination boundaries, not proof of simultaneous execution.

## Parallel workstreams

| Lane | Issue scope | Ownership boundary |
| --- | --- | --- |
| Task UX | #169 #170 #89 | Today, capture and editor widgets |
| Focus | #171 | Timer UI, lifecycle and time tracking |
| Offline/data | #172 #21 | API, sync contract, persistence and reconciliation |
| UX quality | #173 #91 #86 | Accessibility, visual regression and screenshots |
| Delivery | #120 #14 #76 | Android release, notifications and readiness |

Each execution lane owns one issue, one branch and one PR at a time. Before starting, reserve changed paths in the control plane. If two lanes need the same file, serialize or explicitly stack dependent PRs. Do not merge independent changes merely to save time.

## State machine and evidence

`queued -> claimed -> implementing -> validating -> review -> merged -> released`, with explicit `blocked`, `failed`, and `cancelled` transitions. Record attempts and resumable checkpoints. An implementation cannot self-certify review or production readiness; rely on independent reviewer evidence and required CI gates.

Every PR must provide:
1. Issue and acceptance criteria; changed-path ownership; risk and rollback notes.
2. Actual diff and tests; format, analysis, widget/unit tests, web build and applicable Android checks.
3. For UI: actual CI screenshots or artifacts reviewed at narrow and large text scales, RTL/Persian digits/Vazirmatn, light/dark, safe areas and 48px targets. If artifacts are unavailable, mark visual gate **blocked**, never substitute stock images.
4. Independent functional review, then required CI/visual gate review; only then merge to `main`.
5. Deployment/release only from verified `main`; verify artifact version, signing and install/update flow before reporting success.

## High-risk offline gate

No offline/data PR merges without automated evidence of authenticated owner isolation (private objects return 404), idempotent repeated requests, conflicting updates, out-of-order replay, tombstones/deletion, recovery after interrupted sync, cursor consistency and rollback. Keep server authoritative. A missing test blocks merge.

## Reporting

Only announce verified PR creation/merge, published release, or a specific user-action blocker. Report real run IDs and links; no fabricated agent counts, screenshots, green checks or deployments. Stop the follow-up when acceptance criteria and release verification are complete.

Existing `AGENTS.md` and `DESIGN.md` remain authoritative for product-specific rules; this contract supplements, never overrides, them.
