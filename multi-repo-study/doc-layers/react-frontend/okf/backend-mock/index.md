---
type: concept
title: Backend mock — MSW + in-memory db
generated:
  by: reference_agent/claude-sonnet-5
  at: "2026-09-28"
sources:
  - apps/react-vite/src/testing/mocks/db.ts
  - apps/react-vite/src/testing/mocks/handlers/index.ts
  - apps/react-vite/src/testing/mocks/handlers/discussions.ts
---

# Backend mock — MSW + in-memory db

There is no real backend for this app. Every network call the frontend makes is
intercepted by [MSW](https://mswjs.io) and answered by an in-memory data store.

- `src/testing/mocks/db.ts` defines the data models (`user`, `team`, `discussion`,
  `comment`) via `@mswjs/data`'s `factory()`. This is the closest thing to a schema
  in this repo — adding a field here is the mocked equivalent of a migration (see
  `../../.agents/skills/extend-mock-backend/SKILL.md`).
- `src/testing/mocks/handlers/<resource>.ts` — one file per resource, each exporting
  an array of `http.get/post/patch/delete` handlers. Every handler follows the same
  shape: `await networkDelay()`, then `requireAuth(cookies)` (and `requireAdmin`
  for writes), then a `db.<model>.findMany/create/update/delete(...)` call, wrapped
  in try/catch returning a 500 with `{ message }` on unexpected failure.
- `handlers/index.ts` aggregates all resource handler arrays plus one inline
  `/healthcheck` handler.
- This same handler set is installed in two places: `src/testing/setup-tests.ts`
  (for `vitest`) and the app's own mock worker bootstrap for local `dev` when
  `VITE_APP_ENABLE_API_MOCKING=true` — so tests and local development exercise
  *identical* backend behavior, not a separate lighter test double.
- Writes call `persistDb('<model>')` afterward, which serializes the in-memory store
  to `mocked-db.json` so local-dev state survives a page reload — not relevant to
  test runs, which don't rely on persistence.

Because handlers run real HTTP semantics (status codes, JSON parsing, `URL`/query
param parsing) rather than being simple function mocks, a test that exercises a
feature end-to-end is exercising this mock server too, not bypassing it.
