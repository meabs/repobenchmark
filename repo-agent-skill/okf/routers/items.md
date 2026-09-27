---
type: Router
title: items
description: CRUD for items, scoped to the owning user.
resource: backend/app/api/routes/items.py
tags: [api, items]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: items
    resource: backend/app/api/routes/items.py
    title: Source file this concept describes
stale_after: 2027-03-25
---

# items

Prefix: `/items`. Every route requires a bearer token (`CurrentUser`).

| Method | Path | Notes |
|---|---|---|
| GET | `/items/` | Superusers see all items; everyone else sees only their own. Paginated (`skip`/`limit`), ordered by `created_at desc`. |
| GET | `/items/{id}` | 404 if missing, 403 if not owner and not superuser. |
| POST | `/items/` | `owner_id` is forced to `current_user.id` server-side — not settable by the client. |
| PUT | `/items/{id}` | Partial update (`exclude_unset`); same 404/403 ownership rules as GET. |
| DELETE | `/items/{id}` | Same ownership rules. |

Ownership check (`not current_user.is_superuser and item.owner_id != current_user.id`)
is duplicated across `read_item`/`update_item`/`delete_item` — see
[tables/item](../tables/item.md)'s note on this being application-enforced, not a DB
constraint.
