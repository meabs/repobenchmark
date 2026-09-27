---
name: model-field-change
description: Add or change a field on a SQLModel model in this repo — which of the Base/table/Public/Create/Update classes need it, and what else a field change implies (migration, endpoint updates).
---

# Add or change a field on a model

1. Edit `backend/app/models.py`. This template puts the DB table and its API
   request/response variants in one file — a field usually needs to appear in more
   than one class:
   - The `*Base` class if every variant shares it.
   - The table class itself (`table=True`) if it's persisted.
   - `*Public` if it should ever be returned by the API — **do not** add it there by
     default; check whether it's safe to expose first (e.g. never add a password or
     hash field to a `*Public` class).
   - `*Create`/`*Update` if clients should be able to set it.
2. Write a migration — the schema is not created from models at runtime. See the
   `write-migration` skill.
3. If the field affects an existing endpoint's behavior (e.g. a new filter), update
   that route in `backend/app/api/routes/`. See the `add-api-endpoint` skill for the
   conventions those routes follow.
4. When you're done, see the `verify-work` skill before calling it complete.
