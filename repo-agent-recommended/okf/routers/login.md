---
type: Router
title: login
description: Auth, password recovery/reset.
resource: backend/app/api/routes/login.py
tags: [api, auth]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: login
    resource: backend/app/api/routes/login.py
    title: Source file this concept describes
stale_after: 2027-03-25
---

# login

No path prefix (routes are at the API root, e.g. `/api/v1/login/access-token`).

| Method | Path | Auth | Notes |
|---|---|---|---|
| POST | `/login/access-token` | none | OAuth2 password flow; returns a `Token` (JWT). See note below. |
| POST | `/login/test-token` | bearer | Returns the current user — a way to verify a token is valid. |
| POST | `/password-recovery/{email}` | none | Always returns the same success `Message` whether or not the email exists (prevents email enumeration). |
| POST | `/reset-password/` | none | Takes the recovery token + new password. |
| POST | `/password-recovery-html-content/{email}` | superuser | Returns the raw recovery email's HTML — for previewing the email template, not part of the actual recovery flow. |

See [tables/user](../tables/user.md) for the underlying table.

## Why `/login/access-token` always takes about as long to fail

`backend/app/crud.py`'s `authenticate()` looks up the user by email; if none is found,
it still runs `verify_password` against a fixed `DUMMY_HASH` before returning `None`.
This is a deliberate timing-attack mitigation, not dead/wasteful code: without it, a
login against a nonexistent email would return faster than one against a real email
with a wrong password, letting response time be used to enumerate valid accounts. If
you're touching `authenticate()`, keep this call even though its result is discarded.
