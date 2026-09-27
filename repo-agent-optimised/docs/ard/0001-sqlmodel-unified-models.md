# 0001. Unify ORM models and API schemas with SQLModel

## Status
Accepted (in effect throughout `backend/app/models.py`)

## Context
A typical FastAPI + SQLAlchemy app defines two parallel sets of classes for every
entity: SQLAlchemy ORM models for the DB layer, and Pydantic models for request/response
validation. Keeping both in sync by hand is a common source of drift (a field added to
one and forgotten in the other).

## Decision
Use [SQLModel](https://sqlmodel.tiangolo.com/) so a single class hierarchy serves both
purposes. Concretely, per entity (see `User`/`Item` in `backend/app/models.py`):

- A `*Base` class holds the fields shared by every variant (`UserBase`, `ItemBase`).
- The DB table itself subclasses `*Base` with `table=True` (`User`, `Item`) and adds
  server-side-only fields (`id`, `hashed_password`, `created_at`, relationships).
- Request-shape variants subclass `*Base` or `SQLModel` directly: `UserCreate`,
  `UserRegister`, `UserUpdate`, `UserUpdateMe`, `ItemCreate`, `ItemUpdate`.
- Response-shape variants subclass `*Base` and add back only what's safe to return:
  `UserPublic`, `ItemPublic` (notably never `hashed_password`).

Routes (`backend/app/api/routes/*.py`) always take a `*Create`/`*Update` model as input
and declare a `*Public` model as `response_model` — never the raw table model — so the
DB-only fields can't leak through the API by accident.

## Consequences
- Adding a field means touching `models.py` in one place per variant it should appear
  in, not two parallel files.
- `response_model=UserPublic` (etc.) is a deliberate allowlist, not an
  afterthought — if a new sensitive field is added to `User`, it does not appear in API
  responses until someone explicitly adds it to `UserPublic`.
- Table classes and their Alembic migrations must still be kept in sync manually — see
  `0004-alembic-migrations.md`.
