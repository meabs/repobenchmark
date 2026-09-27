---
name: write-migration
description: Write and apply an Alembic migration in this repo after a schema change — the exact commands, and why autogenerate output needs a manual read before trusting it.
---

# Write a migration

Schema changes go through Alembic, never `SQLModel.metadata.create_all` (that call
exists commented-out in `backend/app/core/db.py` on purpose — leave it commented).

```
cd backend
uv run alembic revision --autogenerate -m "short description"
```

Then **read the generated file** under `backend/app/alembic/versions/` before
trusting it — autogenerate can miss things (e.g. it won't detect a column rename,
it'll see a drop + an add). Apply it locally to confirm it actually runs:

```
uv run alembic upgrade head
```
