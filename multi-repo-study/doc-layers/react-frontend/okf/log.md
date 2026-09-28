# Log

- Built this bundle by reading `apps/react-vite/src` directly: `features/discussions`
  as the reference feature, `lib/api-client.ts`, `lib/auth.tsx`,
  `lib/authorization.tsx`, `config/paths.ts`, `app/router.tsx`,
  `testing/mocks/db.ts` and `testing/mocks/handlers/discussions.ts`, and one route
  test (`discussions.test.tsx`).
- The env-var trap (`okf/testing/env.md`) was confirmed directly: running `vitest
  run` in a fresh checkout with no `.env` fails all 12 test files with an identical
  Zod error from `src/config/env.ts:28`, and copying `.env.example` to `.env` fixes
  it with no other changes needed.
- Did not investigate `apps/nextjs-app` or `apps/nextjs-pages` — this bundle and its
  skills are scoped to `apps/react-vite` only, per `AGENTS.md`.
