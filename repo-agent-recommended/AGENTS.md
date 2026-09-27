# AGENTS.md

FastAPI + SQLModel + PostgreSQL backend, React/TypeScript frontend. Read this file
first — it only points, it doesn't explain.

- **What things mean, and why they're built that way where it matters** (services, DB
  tables, routers, deployment topology, how they relate — rationale is folded into
  the relevant doc, not a separate tree): [`okf/index.md`](okf/index.md).
- **How to do a specific kind of change**: `.agents/skills/` has one skill per task,
  each with its own scope — open the one(s) whose description matches what you're
  about to do, not all of them:
  - `model-field-change` — add or change a field on a SQLModel model
  - `write-migration` — write and apply an Alembic migration
  - `add-api-endpoint` — add or modify a FastAPI route
  - `regenerate-frontend-client` — regenerate the generated TS API client
  - `add-ui-action` — add a UI action to an existing table/list page
  - `verify-work` — how to actually confirm a change works, not just that it compiles
- **Human setup/running instructions**: `development.md`, `deployment.md` — not
  duplicated here.

Nothing else lives in this file. If you find yourself adding an explanation or a
procedure here, it belongs in `okf/` or one of the skills instead.
