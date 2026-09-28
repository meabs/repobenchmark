# AGENTS.md

The runnable app lives at `apps/react-vite` (the repo also contains `apps/nextjs-app`
and `apps/nextjs-pages`, which are separate, unrelated apps in this monorepo — ignore
them unless a task explicitly names one). `apps/react-vite` is a React + TypeScript +
Vite app built on the "bulletproof-react" architecture: feature folders, TanStack
Query for server state, MSW for a fully mocked backend (there is no real API server —
tests and local dev both run against msw), React Router, React Hook Form + Zod.
Read this file first — it only points, it doesn't explain.

- **What things mean, and why they're built that way where it matters** (feature-folder
  layout, the mocked-backend setup, the env-var convention, routing — rationale is
  folded into the relevant doc, not a separate tree): [`okf/index.md`](okf/index.md).
- **How to do a specific kind of change**: `.agents/skills/` has one skill per task,
  each with its own scope — open the one(s) whose description matches what you're
  about to do, not all of them:
  - `add-feature-route` — add a new feature folder + route to the app
  - `add-form-with-validation` — add a form backed by a Zod schema and React Hook Form
  - `add-list-action` — add a row-level action (like the existing delete button) to
    an existing table/list screen
  - `extend-mock-backend` — add or change an MSW handler and the mocked db model it
    reads/writes
  - `write-component-test` — write a React Testing Library test that exercises MSW
  - `local-dev-setup` — the env-var step required before `vitest` or `dev` will run
    at all (a real, non-obvious trap — read this before assuming the repo "just works")
- **Human setup/running instructions**: `apps/react-vite/README.md` (upstream) — not
  duplicated here.

Nothing else lives in this file. If you find yourself adding an explanation or a
procedure here, it belongs in `okf/` or one of the skills instead.
