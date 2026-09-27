---
type: Table
title: Item
description: A record owned by exactly one User. The app's one example domain entity.
resource: backend/app/models.py
tags: [table]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: models
    resource: backend/app/models.py
    title: Source file this concept describes
stale_after: 2027-03-25
---

# Item

Defined in `backend/app/models.py` as `class Item(ItemBase, table=True)`.

# Schema

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | Primary key |
| `title` | string, 1–255 chars | Required |
| `description` | string \| null, ≤255 | Optional |
| `created_at` | datetime (tz-aware) | Set at insert time |
| `owner_id` | UUID | FK → `user.id`, `nullable=False`, `ondelete="CASCADE"` |

# Relationships

- `owner: User | None` — back-populates `User.items`.

# API-facing variants

- `ItemCreate` — just `ItemBase` (title + description); `owner_id` is set server-side
  from the authenticated user, never client-supplied (see `routers/items.md`).
- `ItemUpdate` — both fields optional (partial update).
- `ItemPublic` — adds `id`, `owner_id`, `created_at` back.

# Authorization rule (enforced in `routers/items.py`, not at the DB layer)

A non-superuser can only read/update/delete items where `item.owner_id == current_user.id`.
Superusers can act on any item. This check is repeated in each of
`read_item`/`update_item`/`delete_item` — there is no row-level security at the
Postgres level, it's application-enforced.

See [routers/items](../routers/items.md) for the endpoints.
