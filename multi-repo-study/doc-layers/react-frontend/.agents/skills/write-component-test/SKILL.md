---
name: write-component-test
description: Write a React Testing Library test in this repo that exercises the real MSW-mocked backend end to end — the test-utils/data-generators to use, and why you must `cp .env.example .env` first (see local-dev-setup).
---

# Write a component test

Reference: `src/app/routes/app/discussions/__tests__/discussions.test.tsx` and
`src/features/auth/components/__tests__/*.test.tsx`.

1. **Before running any test**, see the `local-dev-setup` skill — `vitest` fails on
   every test file identically until `.env` exists.
2. Import `renderApp` (not `render`) from `@/testing/test-utils` for anything that
   needs router context, auth context, or React Query — it wraps the component the
   same way the real app shell does, and most feature UI depends on that context.
   Also import `screen`, `userEvent`, `waitFor`, `within` from the same module (it
   re-exports Testing Library's utilities so tests have one import source).
3. Use the generators in `@/testing/data-generators` (e.g. `createDiscussion()`) to
   build realistic form input rather than inlining ad hoc literal strings — they
   produce values that satisfy the same Zod schemas the real form validates against.
4. Tests run against the real MSW handlers (see `extend-mock-backend`), not mocked
   API functions — assert on rendered UI state after an action (`await
   screen.findByText(...)`), not on whether a function was called. A slow assertion
   after a mutation usually means waiting on `findBy*`/`waitFor`, not adding
   `waitFor(() => {}, { timeout: ... })` blindly.
5. Colocate the test file under a `__tests__/` directory next to the thing it tests
   (component tests) or the route file (route tests) — this is the only layout used
   in the repo; there's no separate top-level `tests/` tree for unit/component tests.
6. Run `npx --yes vitest run` (or `vitest run <path>` for one file) from
   `apps/react-vite` to actually execute — don't infer pass/fail from reading the
   test.
