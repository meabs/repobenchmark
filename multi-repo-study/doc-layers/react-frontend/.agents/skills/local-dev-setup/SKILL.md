---
name: local-dev-setup
description: The one-time env-var step required before `vitest`, `dev`, or any test in this repo will run — skip it and every test file fails identically with a Zod env-validation error that looks unrelated to what you changed.
---

# Local dev / test setup

`apps/react-vite/src/config/env.ts` builds a validated `env` object at import time
via a top-level `createEnv()` call. It reads `import.meta.env`, keeps only keys
prefixed `VITE_APP_` and strips that prefix (`VITE_APP_API_URL` → `API_URL`), then
validates the result against a Zod schema requiring `API_URL` (string, required) and
`ENABLE_API_MOCKING`, `APP_URL`, `APP_MOCK_API_PORT` (optional).

There is a tracked `.env.example` at `apps/react-vite/.env.example` with the right
keys, but **no tracked `.env`** — Vite only reads `.env`/`.env.local`, never
`.env.example`, so a fresh checkout has no env vars until you create one.

**Before running anything** (`vitest`, `vitest run`, `dev`, `build`) in
`apps/react-vite`:

```
cp .env.example .env
```

If you skip this, every single test file fails with the same misleading error
(`Error: Invalid env provided. ... API_URL: Required`, thrown from `env.ts:28`) —
it looks like a broad, systemic failure but it's this one missing file. Don't spend
time investigating individual test files if you see this; check for `.env` first.
