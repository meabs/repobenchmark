---
type: Router
title: private
description: Unauthenticated user creation, mounted only when FASTAPI_ENV=development.
resource: backend/app/api/routes/private.py
tags: [api, dev-only]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: private
    resource: backend/app/api/routes/private.py
    title: Source file this concept describes
stale_after: 2027-03-25
---

# private

Prefix: `/private`. Only mounted at all when `settings.FASTAPI_ENV == "development"`
(`app/api/main.py`) — not present in the route table otherwise.

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/private/users/` | **none** | Creates a `User` directly from `{email, password, full_name, is_verified}`. No email-uniqueness check, no email sent. |

This exists for local dev/test seeding, not as a real product feature. Its safety
depends entirely on `FASTAPI_ENV` never being set to `"development"` in a reachable
deployment — treat changing how that variable is set as a security-relevant change,
not just a dev-convenience toggle.
