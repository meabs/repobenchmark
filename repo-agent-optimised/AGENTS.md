# AGENTS.md

Entry point for AI agents working in this repository. Read this first.

## What this is

A full-stack web application template: FastAPI (Python) backend + React/TypeScript
frontend, PostgreSQL database, Docker Compose deployment. Source: a normalized copy of
[fastapi/full-stack-fastapi-template](https://github.com/fastapi/full-stack-fastapi-template)
— see `../SETUP.md` for exact provenance (commit SHA, license, what was changed).

It's a small CRUD app (users + items, each user owns items) wired up with real
auth, migrations, email flows, and a generated API client — representative of the
scaffolding a much larger product would be built on top of.

## Directory map

| Path | What's there |
|---|---|
| `backend/app/main.py` | FastAPI app instantiation, CORS, router mounting |
| `backend/app/api/main.py` | Combines all routers into one `api_router` |
| `backend/app/api/routes/` | One file per router: `login.py`, `users.py`, `items.py`, `utils.py`, `private.py` |
| `backend/app/api/deps.py` | Shared FastAPI dependencies: DB session, current-user auth |
| `backend/app/models.py` | All SQLModel models (DB tables + API request/response schemas) |
| `backend/app/crud.py` | DB read/write helpers used by routes |
| `backend/app/core/config.py` | `Settings` (env-var driven config), loaded from `.env` |
| `backend/app/core/security.py` | Password hashing, JWT creation |
| `backend/app/alembic/versions/` | DB migrations, in application order |
| `frontend/src/routes/` | File-based routes (TanStack Router) |
| `frontend/src/client/` | Auto-generated TS client from the backend's OpenAPI schema — do not hand-edit |
| `compose.yml` / `compose.override.yml` / `compose.deploy.yml` | Docker Compose service topology |
| `docs/ard/` | Architecture Decision Records — why things are built this way |
| `docs/api/openapi.json` | The backend's real OpenAPI 3.1 schema, exported from the live app object |
| `okf/` | Open Knowledge Format concept docs — what things are, cross-linked |

## Running it

`development.md` already covers this fully (backend, frontend, full Docker Compose
stack) — don't duplicate it here. One thing worth surfacing: after changing backend
routes or schemas, regenerate the frontend client with `bash scripts/generate-client.sh`
(see `docs/ard/0005-generated-typescript-client.md`).

## Before changing backend routes or models

1. Read `docs/api/openapi.json` (or `okf/routers/`) to see the current contract before adding to it.
2. Routes return SQLModel schema classes (`*Public`, `*Create`, `*Update`), never the raw DB table model — see `docs/ard/0001-sqlmodel-unified-models.md`.
3. `app/api/routes/private.py` is only mounted when `FASTAPI_ENV=development` (see `app/api/main.py`) — it's an unauthenticated user-creation endpoint for local seeding, not part of the real API surface. See `docs/ard/0006-env-gated-private-router.md`.
4. After editing `app/models.py`, generate an Alembic migration (`uv run alembic revision --autogenerate -m "..."`) — the DB schema is not auto-created from models at runtime (see `app/core/db.py`).

## Python version note

`backend/app/api/deps.py` uses `except InvalidTokenError, ValidationError:` (no
parentheses) — looks like broken syntax, but it's valid: this project pins Python
≥3.14 (`backend/pyproject.toml`), and [PEP 758](https://peps.python.org/pep-0758/)
makes that exact bare-comma form mean `except (InvalidTokenError, ValidationError):`.
A pre-3.14 linter/`ast.parse()` will wrongly flag it — that's the tool being older
than the language version this repo targets. See `okf/log.md` for why this note
exists (an earlier version of it got this backwards, and it cost real effort).

## More detail

- `docs/ard/` — architecture decisions, one per file, numbered.
- `docs/api/openapi.json` — full API schema.
- `okf/index.md` — Open Knowledge Format knowledge graph (services, tables, routers,
  deployment topology), cross-linked. Read its "Trust tier" note before treating
  anything in `okf/` as verified fact.
