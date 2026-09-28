---
name: extend-mock-backend
description: Add or change an MSW request handler and the mocked db model behind it — there is no real backend in this repo; every API response for both `dev` and tests comes from src/testing/mocks.
---

# Extend the mocked backend (MSW)

This app has no real backend to call. `src/testing/mocks/handlers/*.ts` are MSW
`http.*` handlers keyed by resource (`discussions.ts`, `comments.ts`, `teams.ts`,
`users.ts`, `auth.ts`), aggregated in `handlers/index.ts`, and installed both for
`vitest` (via `src/testing/setup-tests.ts`) and for local `dev` when
`VITE_APP_ENABLE_API_MOCKING=true` (set in `.env.example`/`.env`).

1. The in-memory data model lives in `src/testing/mocks/db.ts` (`@mswjs/data`
   `factory`). To add a field to an existing resource, add it to that resource's
   model object there (e.g. `discussion: { ..., isPinned: Boolean }`) — this is the
   mocked equivalent of a schema migration; there's no separate migration step.
2. Add or edit the handler in the matching `handlers/<resource>.ts` file. Every
   handler in this repo follows the same shape: `await networkDelay()` first, then a
   `try { requireAuth(cookies) [+ requireAdmin(user) if write] ... } catch` that
   returns `HttpResponse.json({ message }, { status: 500 })` on unexpected errors —
   match this, don't let an exception escape unhandled.
3. Use `db.<model>.update(...)` / `db.<model>.create(...)` from `@mswjs/data` for
   writes, and call `await persistDb('<model>')` afterward (every existing write
   handler does this — it's what makes mocked writes survive a page reload in
   `dev`; tests don't rely on persistence but the call is still expected for
   consistency).
4. On the client side, add the corresponding `api/*.ts` function + hook (see the
   `add-feature-route` skill) that calls the new/changed endpoint.
5. Handlers run against real HTTP semantics inside MSW (status codes, JSON bodies) —
   write a `write-component-test`-style test against the real handler rather than
   mocking the API client itself.
