---
type: Router
title: utils
description: Misc operational endpoints.
resource: backend/app/api/routes/utils.py
tags: [api, utils]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: utils
    resource: backend/app/api/routes/utils.py
    title: Source file this concept describes
stale_after: 2027-03-25
---

# utils

Prefix: `/utils`.

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/utils/test-email/` | superuser | Sends a real test email to `email_to` via the configured SMTP settings. `201` on success. |
| GET | `/utils/health-check/` | none | Returns `true`. Used as the `backend` container's Docker healthcheck (`compose.yml`) — see [deployment/topology](../deployment/topology.md). |
