---
type: concept
title: Architecture — feature folders
generated:
  by: reference_agent/claude-sonnet-5
  at: "2026-09-28"
sources:
  - apps/react-vite/src/features/discussions
  - apps/react-vite/src/components/ui
  - apps/react-vite/src/lib/api-client.ts
---

# Architecture — feature folders

`apps/react-vite/src` follows the bulletproof-react layout:

- `app/` — the app shell: `router.tsx` (route table), `provider.tsx` (React Query +
  other top-level providers), `routes/` (route components, grouped `auth/` vs
  `app/<feature>/`, lazy-loaded per route).
- `features/<name>/` — one folder per business feature (`discussions`, `comments`,
  `auth`, `users`, `teams`). Each has `api/` (one file per server operation: a raw
  fetch fn + a `useQuery`/`useMutation` hook) and `components/` (the feature's UI,
  composed from `components/ui`). See [`../backend-mock/index.md`](../backend-mock/index.md)
  for what those API calls actually hit.
- `components/ui/` — generic, feature-agnostic components (`Table`, `Form`, `Button`,
  `Drawer`, `Dialog`, `Notifications`, `Spinner`, ...). Features compose these; they
  never import from `features/*`.
- `lib/` — cross-feature infrastructure shared by multiple features, not a "utils
  dump": `api-client.ts` (the configured Axios instance — global 401 redirect and
  global error-notification wiring live here, once, not per-feature),
  `auth.tsx` (`useUser`, `useLogin`, `useLogout`, `ProtectedRoute`, built on
  `react-query-auth`), `authorization.tsx` (`ROLES`, `POLICIES`, the `<Authorization>`
  gating component).
- `config/` — `paths.ts` (every route path + href-builder, see
  [`../routing/index.md`](../routing/index.md)), `env.ts` (see
  [`../testing/index.md`](../testing/index.md) — env validation and the setup trap).
- `testing/` — MSW handlers + mock db + RTL test utilities (see
  [`../backend-mock/index.md`](../backend-mock/index.md) and
  [`../testing/index.md`](../testing/index.md)).

The `discussions` feature is the most complete example of this whole pattern (list +
detail + create + update + delete, role-gated create, prefetch-on-hover) — used as
the reference in `.agents/skills/add-feature-route/SKILL.md`.
