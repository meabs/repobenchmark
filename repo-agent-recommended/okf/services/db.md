---
type: Service
title: Database
description: PostgreSQL, schema owned by Alembic migrations.
resource: compose.yml
tags: [postgres, database]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: compose
    resource: compose.yml
    title: Source file this concept describes
stale_after: 2027-03-25
---

# Database

PostgreSQL 18 (`compose.yml`'s `db` service). Single database named `app`.

- Connection string: `DATABASE_URL` env var, normalized in `Settings` to force the
  `postgresql+psycopg://` driver scheme regardless of whether `postgres://` or
  `postgresql://` was given (`app/core/config.py::_use_psycopg_driver`).
- Schema is created/evolved exclusively through Alembic migrations under
  `backend/app/alembic/versions/`, not `SQLModel.metadata.create_all` — see
  `../../SKILL.md` for how to write one.
- Data persisted in a named Docker volume (`app-db-data`), survives container
  recreation.
- Tables: see [tables/](../tables/index.md).

## Admin access

`compose.yml` also runs an `adminer` container (routed by Traefik at
`adminer.${DOMAIN}`) as a web UI for inspecting the DB directly — see
[deployment/topology](../deployment/topology.md).
