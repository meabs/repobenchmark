# 0005. Generate the frontend's API client from the backend's OpenAPI schema

## Status
Accepted (`frontend/src/client/`, `scripts/generate-client.sh`)

## Context
Hand-writing and hand-maintaining a TypeScript API client that mirrors a Python
backend's routes and Pydantic/SQLModel schemas is a second source of drift, similar to
the one `0001-sqlmodel-unified-models.md` avoids on the backend side — every backend
route or schema change would otherwise need a matching manual edit on the frontend.

## Decision
`frontend/src/client/` is generated, not hand-written. `scripts/generate-client.sh`:

1. Imports the real FastAPI `app` object and calls `app.openapi()` directly
   (`uv run python -c "import app.main; ...; app.main.app.openapi()"`) — the schema
   comes from the live app, not a separately-maintained spec file.
2. Writes it to `frontend/openapi.json`.
3. Runs the frontend's client generator (`bun run --filter frontend generate-client`)
   against that file.
4. Lints the result.

Each route's `operationId` is controlled by `custom_generate_unique_id` in
`backend/app/main.py` (`f"{route.tags[0]}-{route.name}"`, e.g. `items-read_items`) —
this exists specifically to keep generated client function names short and readable
instead of FastAPI's verbose default.

`docs/api/openapi.json` in this repo is a static, git-committed snapshot produced the
same way — useful for anyone (human or agent) who wants to see the full API contract
without standing up the backend.

## Consequences
- Never hand-edit files under `frontend/src/client/` — the next `generate-client.sh`
  run silently overwrites them.
- Backend route/schema changes are inert on the frontend until `generate-client.sh` is
  re-run; there's no CI check in this repo enforcing that the committed client is
  up to date with the current backend code.
