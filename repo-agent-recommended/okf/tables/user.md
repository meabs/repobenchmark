---
type: Table
title: User
description: Application accounts. One row per user; owns zero or more Items.
resource: backend/app/models.py
tags: [table, auth]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: models
    resource: backend/app/models.py
    title: Source file this concept describes
stale_after: 2027-03-25
---

# User

Defined in `backend/app/models.py` as `class User(UserBase, table=True)`.

# Schema

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key, `default_factory=uuid.uuid4` |
| `email` | string, ≤255 | Unique, indexed |
| `hashed_password` | string | Argon2 (or legacy bcrypt) hash. Never returned by the API. |
| `is_active` | bool | Default `true`. Inactive users are rejected at login and by `get_current_user`. |
| `is_superuser` | bool | Default `false`. Gates admin-only routes via `get_current_active_superuser`. |
| `full_name` | string \| null, ≤255 | Optional |
| `created_at` | datetime (tz-aware) | `default_factory` set at insert time |

# Relationships

- `items: list[Item]` — back-populates `Item.owner`, `cascade_delete=True` (deleting a
  user deletes their items at the ORM level; the FK also has `ondelete="CASCADE"` at the
  DB level, see [item](item.md)).

# API-facing variants (all in `models.py`)

- `UserCreate` — used by admin-only `POST /users/`, includes `password`.
- `UserRegister` — used by public `POST /users/signup`, includes `password`, excludes
  `is_active`/`is_superuser` (self-signup can't grant yourself admin).
- `UserUpdate` / `UserUpdateMe` — admin update vs. self-service update (the latter can't
  change `is_active`/`is_superuser`).
- `UpdatePassword` — `current_password` + `new_password`, for `PATCH /users/me/password`.
- `UserPublic` — the only shape ever returned by the API; omits `hashed_password`.

See [routers/users](../routers/users.md) for the endpoints that operate on this table.
