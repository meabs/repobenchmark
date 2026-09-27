# 0004. Alembic migrations own the DB schema, not `SQLModel.metadata.create_all`

## Status
Accepted (`backend/app/alembic/`, `backend/app/core/db.py`)

## Context
SQLModel/SQLAlchemy can create tables directly from model metadata
(`SQLModel.metadata.create_all(engine)`), which is convenient for a throwaway
prototype but has no notion of incremental change — it can't alter an existing table,
and gives no history of how the schema evolved.

## Decision
`backend/app/core/db.py` explicitly does **not** call `create_all`; the line is present
but commented out with a note: "Tables should be created with Alembic migrations."
Schema changes are instead checked into `backend/app/alembic/versions/` as ordered,
named migrations (currently: initialize models → add `created_at` to `User`/`Item` →
replace integer PKs with UUIDs → add string length limits → add cascade-delete on the
`User → Item` relationship). Each migration is generated from the current
`app.models` state via `uv run alembic revision --autogenerate` and hand-reviewed
before committing.

`init_db()` (also in `core/db.py`) only seeds the first superuser account from
`FIRST_SUPERUSER`/`FIRST_SUPERUSER_PASSWORD` — it assumes the schema already exists.

## Consequences
- Changing `backend/app/models.py` without also writing a matching Alembic migration
  leaves the running DB out of sync with the code — SQLAlchemy will not catch this at
  import time, only at query time.
- Migration order matters and is enforced by Alembic's `down_revision` chain in each
  file under `alembic/versions/` — do not reorder or delete a migration that's already
  been applied anywhere.
