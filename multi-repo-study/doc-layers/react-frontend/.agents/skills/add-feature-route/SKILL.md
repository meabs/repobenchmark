---
name: add-feature-route
description: Add a new top-level feature (its own folder under src/features, an API layer, and a routed page) to this app — the file layout and router wiring convention to follow, using the discussions feature as the reference example.
---

# Add a new feature + route

Follow the `discussions` feature (`src/features/discussions/`) as the concrete
template — it's the most complete example of this pattern in the repo.

1. Create `src/features/<name>/` with `api/` (one file per operation, e.g.
   `get-<name>s.ts`, `create-<name>.ts`) and `components/` (one file per UI piece,
   e.g. `<name>s-list.tsx`, `create-<name>.tsx`).
2. Each `api/*.ts` file exports: the raw fetch function (using `api` from
   `@/lib/api-client`, which already injects `Accept: application/json` and handles
   401 redirects globally — don't add your own error handling for that), a
   `queryOptions`/`useQuery` hook for reads (see `get-discussions.ts`) or a
   `useMutation` hook for writes (see `create-discussion.ts`, including the
   `queryClient.invalidateQueries` call on success — mutations must invalidate the
   list query key or the UI won't refresh).
3. Add the route path to `src/config/paths.ts` under the appropriate section (`app.*`
   for authenticated routes) with both `path` and a `getHref()` helper — every
   existing route has both; don't link with a raw string elsewhere.
4. Add a route file under `src/app/routes/app/<name>/` exporting a `clientLoader`
   (prefetches via `queryClient.ensureQueryData`) and a default component, then
   register it as a `lazy: () => import(...)` entry in `src/app/router.tsx` inside
   the `paths.app.root` children array, matching the discussions entries there.
5. If the feature needs authorization gating, wrap the relevant UI in
   `<Authorization allowedRoles={[ROLES.ADMIN]}>` from `@/lib/authorization` (see
   `create-discussion.tsx`) rather than checking `useUser().data.role` inline.
6. See the `write-component-test` skill before calling it done.
