---
name: verify-work
description: How to actually confirm a backend or frontend change works in this repo, beyond "the code looks right" — which tests to run, in what order, and why passing pytest alone isn't enough for a UI change.
---

# Verify the work is actually done

Don't stop at "the code looks right" — confirm it, in this order:

1. **Backend tests**: `cd backend && FASTAPI_ENV=development uv run pytest tests/`
   — needs a real Postgres reachable at the configured `DATABASE_URL`, migrated to
   `head` first (`uv run alembic upgrade head`).
2. **Frontend build**: `cd frontend && bun run build` (or the npm equivalent) —
   catches type errors the editor might not.
3. **Frontend e2e**: `frontend/tests/*.spec.ts` are real Playwright tests that drive
   the actual UI against a running stack. Run them (`bun run test`) if the stack is
   up, or at minimum read the existing specs for the page you changed and add a case
   for the new behavior — a passing backend test suite does not tell you the button
   you added actually works.
4. **Exercise the new behavior directly**: for a new endpoint, a real request against
   a running server (not just a unit test) is the closest thing to how a user will
   actually hit it. For a new UI control, look at what it renders, not just that it
   compiles.

A change that passes `pytest` but was never clicked through in the UI or hit with a
real request is not verified — it's untested code that happens to compile.
