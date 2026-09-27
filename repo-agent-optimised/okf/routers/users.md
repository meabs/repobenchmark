---
type: Router
title: users
description: User CRUD — self-service and admin.
resource: backend/app/api/routes/users.py
tags: [api, users]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: users
    resource: backend/app/api/routes/users.py
    title: Source file this concept describes
stale_after: 2027-03-25
---

# users

Prefix: `/users`.

| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/users/` | superuser | List all users, paginated (`skip`/`limit`). |
| POST | `/users/` | superuser | Create a user (admin path — can set `is_superuser`). |
| GET | `/users/me` | bearer | Current user. |
| PATCH | `/users/me` | bearer | Self-update (`full_name`/`email` only — rejects with 409 if the new email is already taken by someone else). |
| PATCH | `/users/me/password` | bearer | Requires `current_password`; rejects if new == old. |
| DELETE | `/users/me` | bearer | Self-delete — refused (403) if `is_superuser`. |
| POST | `/users/signup` | none | Public self-registration via `UserRegister` (can't set `is_superuser`/`is_active`). |
| GET | `/users/{user_id}` | bearer | Any user can fetch their own record by id; fetching someone else's requires superuser. |
| PATCH | `/users/{user_id}` | superuser | Admin update of any user. |
| DELETE | `/users/{user_id}` | superuser | Deletes the user's items first (`DELETE FROM item WHERE owner_id = ...`), then the user. Refuses (403) if `user_id == current_user.id` (a superuser can't delete themselves this way — see `delete_user_me` for self-delete, which has the same self-superuser restriction). |

See [tables/user](../tables/user.md) for the schema, [ARD 0001](../../docs/ard/0001-sqlmodel-unified-models.md) for why request/response shapes differ from the table.
