---
type: Service
title: Backend
description: FastAPI application serving the REST API (and, in production, the built frontend as static files).
resource: backend/app/main.py
tags: [python, fastapi, api]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: main
    resource: backend/app/main.py
    title: Source file this concept describes
stale_after: 2027-03-25
---

# Backend

FastAPI app defined in `backend/app/main.py`. Entry point: `app` (a `FastAPI` instance).

## Responsibilities

- Serves the REST API under `/api/v1` (see [routers](../routers/index.md)).
- In production, also serves the built frontend as static files from `app/frontend`
  (`app.frontend("/", directory=FRONTEND_DIR)`) — so the `backend` container is the
  only one that needs to be reachable from outside Docker (see
  [deployment/topology](../deployment/topology.md)).
- Talks to [db](db.md) via SQLModel/SQLAlchemy, engine created in `app/core/db.py`.
- Optionally reports errors to Sentry if `SENTRY_DSN` is set and `FASTAPI_ENV` is not
  `"development"` (`app/main.py`).

## Key files

| File | Role |
|---|---|
| `app/main.py` | App instantiation, CORS, router + frontend mounting |
| `app/api/main.py` | Aggregates routers into `api_router` |
| `app/api/deps.py` | `SessionDep` (DB session), `CurrentUser`/`TokenDep` (auth) |
| `app/core/config.py` | `Settings`, loaded from `../.env` |
| `app/core/security.py` | Password hashing, JWT creation |
| `app/models.py` | All SQLModel models |
| `app/crud.py` | DB read/write helpers |

## Config

Configured entirely through environment variables (`app/core/config.py`'s `Settings`,
a `pydantic_settings.BaseSettings`), loaded from a `.env` file one directory above
`backend/`. Required vars have no default and raise at startup if missing:
`SECRET_KEY`, `PROJECT_NAME`, `DATABASE_URL`, `FIRST_SUPERUSER`,
`FIRST_SUPERUSER_PASSWORD`.

Related: [ARD 0002 — JWT bearer auth](../../docs/ard/0002-jwt-bearer-auth.md),
[ARD 0006 — env-gated private router](../../docs/ard/0006-env-gated-private-router.md).
