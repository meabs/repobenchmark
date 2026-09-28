---
type: concept
title: Routing — paths, router, and auth-gating
generated:
  by: reference_agent/claude-sonnet-5
  at: "2026-09-28"
sources:
  - apps/react-vite/src/config/paths.ts
  - apps/react-vite/src/app/router.tsx
  - apps/react-vite/src/lib/auth.tsx
---

# Routing

- `src/config/paths.ts` is the single source of truth for every route: each entry
  has a `path` (used in the router table) and a `getHref(...)` function (used
  everywhere a component links to it). No component builds a route URL by hand;
  they all call `paths.<section>.<name>.getHref(...)`.
- `src/app/router.tsx` builds a `createBrowserRouter` table from `paths`. Every
  route below `paths.app.root` is lazy-loaded (`lazy: () => import(...)`) and
  wrapped in `<ProtectedRoute>` (from `src/lib/auth.tsx`, redirects to login if
  `useUser()` has no data) at the `app.root` level — individual child routes don't
  each re-check auth.
- Route modules under `src/app/routes/` export a `clientLoader(queryClient)` (runs
  before the route renders, typically `queryClient.ensureQueryData(...)` for the
  route's primary data) and a default-exported component. `router.tsx`'s `convert()`
  helper adapts that module shape into what `react-router`'s `lazy` expects.
- Role-based UI gating (as opposed to route access) is a separate, narrower concern
  handled by `<Authorization>` (`src/lib/authorization.tsx`) — see
  `../architecture/index.md`. A route being reachable doesn't mean every action on
  it is available to every authenticated user; `<Authorization allowedRoles={[...]}>`
  controls that at the component level (e.g. only `ROLES.ADMIN` sees the "Create
  Discussion" button).
