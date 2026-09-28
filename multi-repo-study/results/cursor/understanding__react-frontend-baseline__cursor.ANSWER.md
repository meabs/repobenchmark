# Codebase answers (`apps/react-vite`)

All paths below are relative to `apps/react-vite` unless noted.

## 1. Create Discussion, from the button click to the new row

The signed-in admin is already on `DiscussionsRoute` (`src/app/routes/app/discussions/discussions.tsx`). That route renders `CreateDiscussion` and `DiscussionsList`. `DiscussionsList` is already subscribed to the discussions query (see step 13). The click sequence is:

1. **`CreateDiscussion`** (`src/features/discussions/components/create-discussion.tsx`, lines 13–73) renders the trigger as a `Button` whose label is `Create Discussion` (lines 30–33), inside `FormDrawer`'s `triggerButton`.
2. **`FormDrawer`** (`src/components/ui/form/form-drawer.tsx`, lines 24–68) renders that button through **`DrawerTrigger`** with `asChild` (line 50). **`Drawer`** and **`DrawerTrigger`** are the `@radix-ui/react-dialog` `Root` and `Trigger` re-exports in `src/components/ui/drawer/drawer.tsx` (lines 8–10). The `Button` itself is the `forwardRef` component in `src/components/ui/button/button.tsx` (lines 46–74). It does not add its own click handler.
3. Radix opens the dialog and calls the controlled `onOpenChange(true)` callback (form-drawer lines 42–48), which calls **`open`** from **`useDisclosure`** (`src/hooks/use-disclosure.ts`, lines 3–10). `open` does `setIsOpen(true)`. The drawer body mounts, including the `Form`.
4. **`Form`** (`src/components/ui/form/form.tsx`, lines 182–205) calls `useForm({ resolver: zodResolver(schema) })`. `schema` is **`createDiscussionInputSchema`** (`src/features/discussions/api/create-discussion.ts`, lines 10–13): `title` and `body` are each `z.string().min(1, 'Required')`. The render prop calls `register('title')` and `register('body')`.
5. **`Input`** (`src/components/ui/form/input.tsx`, lines 14–31) and **`Textarea`** (`src/components/ui/form/textarea.tsx`, lines 14–30) spread that `registration` onto the native `<input>` / `<textarea>`. Typing updates React Hook Form state.
6. The Submit control is a second `Button` in `CreateDiscussion` (lines 36–44): `type="submit"` and `form="create-discussion"`. It sits in `DrawerFooter`, outside the `<form>`, and the `form` attribute targets the form whose `id` is `create-discussion` (`Form` sets that `id` on the `<form>`, form.tsx line 199).
7. Submit runs `onSubmit={form.handleSubmit(onSubmit)}` (form.tsx line 198). `handleSubmit` runs the Zod resolver first. When both fields are non-empty, it calls the callback in `CreateDiscussion` (lines 49–51): `createDiscussionMutation.mutate({ data: values })`.
8. **`useCreateDiscussion`** (`src/features/discussions/api/create-discussion.ts`, lines 29–46) is `useMutation`. Its `mutationFn` is **`createDiscussion`** (lines 17–23), which calls `api.post('/discussions', data)`.
9. **`api`** is the Axios instance in `src/lib/api-client.ts` (lines 16–18), `baseURL: env.API_URL`. The request interceptor **`authRequestInterceptor`** (lines 7–14) sets `headers.Accept = 'application/json'` and `config.withCredentials = true`.
10. The MSW worker (started at boot by **`enableMocking`** in `src/testing/mocks/index.ts`, called from `src/main.tsx`) matches the POST handler in **`discussionsHandlers`** (`src/testing/mocks/handlers/discussions.ts`, lines 133–156):
    - **`networkDelay`** (`src/testing/mocks/utils.ts`, lines 32–37). Outside tests this is a random 300–1000ms `delay`.
    - **`requireAuth(cookies)`** (`utils.ts`, lines 80–104). It reads cookie `bulletproof_react_app_token` (`AUTH_COOKIE`, line 78), `decode`s it, and loads the user with `db.user.findFirst`.
    - **`requireAdmin(user)`** (`utils.ts`, lines 106–110). An `ADMIN` passes; a non-admin throws `Unauthorized`, which this handler turns into HTTP 500.
    - **`db.discussion.create`** (handler lines 143–147) with `teamId: user.teamId`, `authorId: user.id`, plus `title` and `body`. `@mswjs/data` fills `id` (`primaryKey(nanoid)`) and `createdAt` (`Date.now`) from the model in `src/testing/mocks/db.ts`.
    - **`persistDb('discussion')`** (`db.ts`, lines 80–85) copies `db.discussion.getAll()` into storage (see question 3).
    - `HttpResponse.json(result)` returns the created discussion object.
11. The response interceptor (`api-client.ts`, lines 21–24) returns `response.data`, so the mutation resolves to that discussion object.
12. `useMutation`'s `onSuccess` (`create-discussion.ts`, lines 37–42) runs first:
    - `queryClient.invalidateQueries({ queryKey: getDiscussionsQueryOptions().queryKey })`.
    - **`getDiscussionsQueryOptions()`** called with no page (`src/features/discussions/api/get-discussions.ts`, lines 20–27) has query key `['discussions']` (the `page ? ... : ['discussions']` branch).
    - It then calls the `mutationConfig.onSuccess` from `CreateDiscussion` (lines 17–21), which calls **`addNotification`** on the Zustand store **`useNotifications`** (`src/components/ui/notifications/notifications-store.ts`, lines 17–24) with title `Discussion Created`.
13. The list is the active query from **`useDiscussions`** in **`DiscussionsList`** (`src/features/discussions/components/discussions-list.tsx`, lines 19–27). Page comes from `useSearchParams().get('page')`, defaulting to `1`. Its key is `['discussions', { page }]`. TanStack Query treats `invalidateQueries` as a prefix match, so `['discussions']` invalidates that key and refetches it. (`queryConfig.queries.staleTime` is 60s in `src/lib/react-query.ts`, but invalidation still refetches an active query.)
14. The refetch calls **`getDiscussions(page)`** (`get-discussions.ts`, lines 7–18): `api.get('/discussions', { params: { page } })`, through the same Axios interceptor.
15. The GET handler (`discussions.ts`, lines 19–79) calls `requireAuth`, then `db.discussion.count` and **`db.discussion.findMany`** with `where.teamId.equals = user.teamId`, `take: 10`, `skip: 10 * (page - 1)`. Each row drops `authorId` and attaches `author` from `db.user.findFirst` passed through **`sanitizeUser`** (`utils.ts`, lines 50–51), which omits `password` and `iat`. The handler returns `{ data: result, meta: { page, total, totalPages } }`.
16. Axios unwraps `response.data`. `useQuery` updates. `DiscussionsList` re-renders and passes `discussionsQuery.data.data` to **`Table`** (`src/components/ui/table/table.tsx`, lines 138–176). The Title column has no custom `Cell`, so line 166 renders `` `${entry[field]}` ``, which is the new title. The row is visible.

On the same success, `FormDrawer`'s effect (form-drawer lines 33–37) sees `isDone={createDiscussionMutation.isSuccess}` and calls **`close`** from `useDisclosure`, which closes the drawer.

The route loader **`clientLoader`** (`discussions.tsx`, lines 10–23) is what first populated the cache on navigation (`getDiscussionsQueryOptions({ page })` via `fetchQuery`). It does not run again on invalidate. The row appears because `DiscussionsList`'s `useQuery` refetches.

### What a non-ADMIN sees on that screen

They still get the discussions page: `ContentLayout` title `Discussions` (`src/components/layouts/content-layout.tsx`) and `DiscussionsList` (the table, or the empty state). The **Create Discussion** button is absent. The top-right wrapper in `DiscussionsRoute` (lines 29–31) renders nothing. Each row's **Delete Discussion** control is absent for the same reason (`DeleteDiscussion` in `src/features/discussions/components/delete-discussion.tsx`, lines 28–51).

The mechanism is the **`Authorization`** component in `src/lib/authorization.tsx` (lines 63–82), used as `<Authorization allowedRoles={[ROLES.ADMIN]}>` with no `forbiddenFallback`. It calls **`checkAccess`** from **`useAuthorization`** (lines 28–44). `checkAccess` returns `allowedRoles.includes(user.data.role)` (line 38). For role `USER` that is false, so `Authorization` returns `forbiddenFallback`, which defaults to `null` (line 66). The button is never mounted.

`user.data.role` comes from **`useUser`** (`configureAuth` in `src/lib/auth.tsx`). A user who registers by joining an existing team is stored as `USER`; a user who creates a team is stored as `ADMIN` (`src/testing/mocks/handlers/auth.ts`, lines 53–78).

## 2. Why `npx vitest run` fails all 12 files on a fresh checkout

Run from `apps/react-vite`. All 12 suites fail before any test runs, with the same error:

```
Error: Invalid env provided.
The following variables are missing or invalid:
- API_URL: Required
```

Thrown by **`createEnv`** at `src/config/env.ts:28`. Stack: `createEnv` (`env.ts:41`, the `export const env = createEnv()` call) imported by `src/testing/mocks/handlers/index.ts:2`.

Cause: `src/testing/setup-tests.ts` (the Vitest `setupFiles` entry in `vite.config.ts`) imports `server` from `src/testing/mocks/server.ts`, which spreads `handlers`, which imports `@/config/env`. `createEnv` runs at import time. It only copies `import.meta.env` keys that start with `VITE_APP_` (env.ts lines 15–23). `API_URL` is `z.string()` with no default (line 5). `.env` is gitignored (`apps/react-vite/.gitignore`), and a fresh checkout only has `.env.example`. Vite does not load `.env.example`, so `VITE_APP_API_URL` is absent, `API_URL` fails validation, and every suite dies while loading setup.

One-line fix, from `apps/react-vite` (the setup line in that app's README):

```bash
cp .env.example .env
```

`.env.example` sets `VITE_APP_API_URL=https://api.bulletproofapp.com`, which `createEnv` maps to `API_URL`. After that copy, `npx vitest run` passes all 12 files (21 tests).

## 3. What `db.discussion.findMany` queries

There is no database server behind this call. `db` is an in-memory collection from **`factory(models)`** in `@mswjs/data`, created in `src/testing/mocks/db.ts` line 39.

The discussion shape is the `discussion` model in that same file (lines 22–29):

- `id`: `primaryKey(nanoid)`
- `title`: `String`
- `body`: `String`
- `authorId`: `String`
- `teamId`: `String`
- `createdAt`: `Date.now`

The GET handler (`src/testing/mocks/handlers/discussions.ts`, lines 42–51) queries that in-memory model: `teamId` equals the signed-in user's `teamId`, `take: 10`, `skip: 10 * (page - 1)`.

Between page reloads in local browser dev, **`persistDb`** (`db.ts`, lines 80–85) writes the model via **`storeDb`** (lines 69–78) into `window.localStorage` under the key **`msw-db`**. On the next load, `src/main.tsx` calls **`enableMocking`** (`src/testing/mocks/index.ts`), which calls **`initializeDb`** (`db.ts`, lines 87–97). `initializeDb` reads that key through **`loadDb`** (lines 64–66) and `model.create`s each saved row back into the factory. `persistDb` returns immediately when `process.env.NODE_ENV === 'test'` (line 81), so tests do not touch that storage. The Node branch of `loadDb` / `storeDb` uses a file named `mocked-db.json`; the browser dev path is `localStorage`.

## 4. Automatic redirect in `src/lib/api-client.ts`

HTTP **401** (`error.response?.status === 401`, lines 33–38).

It sets `window.location.href` to **`paths.auth.login.getHref(redirectTo)`** (`src/config/paths.ts`, lines 13–16), which is:

```text
/auth/login?redirectTo=<encodeURIComponent(redirectTo)>
```

The query parameter name is **`redirectTo`**.

`redirectTo` is computed on lines 34–36 as `new URLSearchParams().get('redirectTo') || window.location.pathname`. That `URLSearchParams` is constructed with no input, so `get('redirectTo')` is always `null`, and the value attached is `window.location.pathname`.

## 5. `VITE_APP_API_URL` → `env.API_URL`

The function is **`createEnv`** in `src/config/env.ts` (lines 3–39). The app reads the result as `export const env = createEnv()` (line 41), and `api-client.ts` uses `env.API_URL`.

The rule is the `reduce` over `Object.entries(import.meta.env)` (lines 15–23): if a key `startsWith('VITE_APP_')`, copy its value onto the object under `key.replace('VITE_APP_', '')`. `replace` removes the first occurrence of that prefix, so `VITE_APP_API_URL` becomes the key `API_URL`. Keys that do not start with `VITE_APP_` are dropped. `EnvSchema` then checks `API_URL` with `z.string()` and `createEnv` returns `parsedEnv.data`.
