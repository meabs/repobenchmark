---
type: concept
title: Testing — Vitest, RTL, and the env-var trap
generated:
  by: reference_agent/claude-sonnet-5
  at: "2026-09-28"
sources:
  - apps/react-vite/src/config/env.ts
  - apps/react-vite/src/testing/test-utils.tsx
  - apps/react-vite/.env.example
  - apps/react-vite/src/app/routes/app/discussions/__tests__/discussions.test.tsx
---

# Testing — Vitest, RTL, and the env-var trap

Tests run with Vitest + `jsdom` + React Testing Library, configured in
`vite.config.ts`'s `test` block (`setupFiles: './src/testing/setup-tests.ts'`).

## The env-var trap (verified directly)

`src/config/env.ts` runs `createEnv()` at module import time — before any test
body executes. It reads `import.meta.env`, keeps only `VITE_APP_*`-prefixed keys
and strips that prefix, then validates the result against a Zod schema requiring
`API_URL`. Vite only loads `.env`/`.env.local` files, never `.env.example`, and this
repo ships `.env.example` but no tracked `.env`. Result: on a completely fresh
checkout, every test file — regardless of what it tests — fails identically with:

```
Error: Invalid env provided.
The following variables are missing or invalid:
- API_URL: Required
```

The fix is exactly `cp .env.example .env` in `apps/react-vite`, nothing more — the
values in `.env.example` (`VITE_APP_API_URL=https://api.bulletproofapp.com`,
`VITE_APP_ENABLE_API_MOCKING=true`) are sufficient for both `dev` and tests, since
`VITE_APP_ENABLE_API_MOCKING=true` is what turns on MSW (see
[`../backend-mock/index.md`](../backend-mock/index.md)) — the app never actually
calls the real `api.bulletproofapp.com` host in this configuration.

See `.agents/skills/local-dev-setup/SKILL.md` for the one-line fix. This is
documented here as a fact about the repo, not "fixed" in the fixture itself — a
fresh checkout of the real upstream project has the same gap.

## Test conventions

- Tests are colocated in `__tests__/` next to what they test — components, route
  files, hooks, and `lib/` modules all follow this.
- Import `renderApp` (not RTL's own `render`) from `@/testing/test-utils` for
  anything needing router/auth/query context — see
  `discussions.test.tsx` for the fullest example (create → render → delete, through
  real MSW handlers).
- `@/testing/data-generators` produces realistic fake input matching the Zod
  schemas the forms validate against, e.g. `createDiscussion()`.
