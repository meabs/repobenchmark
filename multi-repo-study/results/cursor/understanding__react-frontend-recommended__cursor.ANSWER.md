# Codebase answers

Paths below are relative to `apps/react-vite/` unless noted.

## 1. Create Discussion (ADMIN) and what a non-ADMIN sees

The signed-in user is already on `/app/discussions`. `createAppRouter` in `src/app/router.tsx` (lines 47–52) lazy-loads `src/app/routes/app/discussions/discussions.tsx`. `DiscussionsRoute` (lines 25–43) renders `CreateDiscussion` and `DiscussionsList`. `DiscussionsList` (`src/features/discussions/components/discussions-list.tsx`) is subscribed to the list via `useDiscussions` (lines 24–26), so it is the component that re-renders when the list query updates.

### From the button click to the new row

1. **The button is in the tree only because the role check already passed.** `CreateDiscussion` (`src/features/discussions/components/create-discussion.tsx`, lines 26–71) wraps the drawer in `<Authorization allowedRoles={[ROLES.ADMIN]}>`. `Authorization` (`src/lib/authorization.tsx`, lines 63–81) calls `useAuthorization` (lines 28–47), which calls `useUser` (exported from `configureAuth(authConfig)` in `src/lib/auth.tsx`, lines 75–76; `userFn` is `getUser`, lines 13–17, `GET /auth/me`). `checkAccess` (lines 35–44) returns `allowedRoles.includes(user.data.role)`. `ROLES.ADMIN` is `'ADMIN'` (lines 7–9). For an ADMIN that is true, so `Authorization` renders `children` (line 81).

2. **Click opens the drawer.** The "Create Discussion" `Button` (`src/components/ui/button/button.tsx`, the `Button` forwardRef) is `FormDrawer`'s `triggerButton` (`src/components/ui/form/form-drawer.tsx`, lines 30–50). It is rendered as `<DrawerTrigger asChild>`. `DrawerTrigger` (`src/components/ui/drawer/drawer.tsx`, line 10) is `@radix-ui/react-dialog`'s `Trigger`, and `Drawer` (line 8) is `Dialog.Root`, controlled by `open={isOpen}`. The click makes Radix call `onOpenChange(true)` (form-drawer.tsx lines 42–48), which calls `open` from `useDisclosure` (`src/hooks/use-disclosure.ts`, lines 6 and 10). `open` does `setIsOpen(true)`, so the drawer content (the form) mounts.

3. **Filling the form registers fields through React Hook Form.** `Form` (`src/components/ui/form/form.tsx`, lines 182–204) calls `useForm({ resolver: zodResolver(schema) })` with `createDiscussionInputSchema` (`src/features/discussions/api/create-discussion.ts`, lines 10–13): `title` and `body` are `z.string().min(1, 'Required')`. The render prop's `register('title')` / `register('body')` are spread onto the DOM nodes by `Input` (`src/components/ui/form/input.tsx`, lines 14–28, `{...registration}`) and `Textarea` (`src/components/ui/form/textarea.tsx`, lines 14–28).

4. **Submit.** The footer `Button` (`create-discussion.tsx`, lines 37–44) has `type="submit"` and `form="create-discussion"`, matching the `<form id="create-discussion">` rendered by `Form` (form.tsx lines 196–200). That form's `onSubmit` is `form.handleSubmit(onSubmit)`. `handleSubmit` runs the Zod resolver first. On success it calls the callback in `CreateDiscussion` (lines 49–51): `createDiscussionMutation.mutate({ data: values })`.

5. **Mutation function.** `useCreateDiscussion` (`src/features/discussions/api/create-discussion.ts`, lines 29–46) returns `useMutation` with `mutationFn: createDiscussion`. `createDiscussion` (lines 17–23) calls `api.post('/discussions', data)`.

6. **HTTP client.** `api` (`src/lib/api-client.ts`, lines 16–20) is `Axios.create({ baseURL: env.API_URL })`. The request interceptor `authRequestInterceptor` (lines 7–14) sets `Accept: application/json` and `config.withCredentials = true`, so the auth cookie is sent. There is no real server; the request is intercepted by MSW.

7. **MSW worker (local dev).** `src/main.tsx` (lines 11–16) calls `enableMocking` (`src/testing/mocks/index.ts`, lines 3–9). When `env.ENABLE_API_MOCKING` is true it `initializeDb()`s (see question 3) and `worker.start()`. `worker` (`src/testing/mocks/browser.ts`, line 5) is `setupWorker(...handlers)`. `handlers` (`src/testing/mocks/handlers/index.ts`, lines 13–18) spreads `discussionsHandlers`.

8. **POST handler.** The `http.post(\`${env.API_URL}/discussions\`, ...)` callback (`src/testing/mocks/handlers/discussions.ts`, lines 133–156):
   - `networkDelay()` (`src/testing/mocks/utils.ts`, lines 32–37).
   - `requireAuth(cookies)` (utils.ts lines 80–104). Cookie name is `AUTH_COOKIE` = `bulletproof_react_app_token` (line 78). It `decode`s the token, then `db.user.findFirst` by `id`. Missing/invalid token returns `{ error: 'Unauthorized', user: null }`, and the handler responds `401`.
   - `requireAdmin(user)` (utils.ts lines 106–110) throws `Error('Unauthorized')` unless `user.role === 'ADMIN'`.
   - `db.discussion.create({ teamId: user?.teamId, authorId: user?.id, ...data })` inserts into the in-memory model (question 3). `title` and `body` come from the JSON body.
   - `persistDb('discussion')` (db.ts lines 80–85) writes the collection out (question 3).
   - `HttpResponse.json(result)` returns the created record (HTTP 200).

9. **Axios unwraps the body.** The response interceptor (`api-client.ts`, lines 21–24) returns `response.data`, so the mutation resolves to the created discussion object, not the Axios response.

10. **Cache invalidation.** `useMutation`'s `onSuccess` in `useCreateDiscussion` (create-discussion.ts lines 37–42) runs first: `queryClient.invalidateQueries({ queryKey: getDiscussionsQueryOptions().queryKey })`. Called with no page, `getDiscussionsQueryOptions` (`src/features/discussions/api/get-discussions.ts`, lines 20–26) uses `queryKey: ['discussions']` (the `page ? ... : ['discussions']` branch). `@tanstack/react-query` `^5.32.0` partial-matches query keys, so this invalidates the active list query and refetches it. That query's key is `['discussions', { page }]` from `useDiscussions` → `getDiscussionsQueryOptions({ page })` (get-discussions.ts lines 34–41). `DiscussionsList` passes `page: +(searchParams.get('page') || 1)` (discussions-list.tsx lines 22–26), so the key is `['discussions', { page: 1 }]` on the first page. `invalidateQueries` refetches active queries regardless of the 60s `staleTime` in `queryConfig` (`src/lib/react-query.ts`, lines 3–10). The `QueryClient` lives in `AppProvider` (`src/app/provider.tsx`, lines 17–23).

11. **Caller `onSuccess`.** After invalidation, `useCreateDiscussion` calls the `mutationConfig.onSuccess` from `CreateDiscussion` (create-discussion.tsx lines 16–23): `addNotification({ type: 'success', title: 'Discussion Created' })` on the Zustand store `useNotifications` (`src/components/ui/notifications/notifications-store.ts`, lines 17–25). `FormDrawer`'s effect (form-drawer.tsx lines 33–37) sees `isDone={createDiscussionMutation.isSuccess}` and calls `close()`, which sets the drawer closed. Neither step is what puts the row on screen.

12. **List refetch.** The invalidated `useQuery` runs `getDiscussions(page)` (get-discussions.ts lines 7–17): `api.get('/discussions', { params: { page } })`, through the same Axios interceptors. The GET handler (`discussions.ts`, lines 19–79) calls `networkDelay`, `requireAuth`, then `db.discussion.count` and `db.discussion.findMany` with `where: { teamId: { equals: user.teamId } }`, `take: 10`, `skip: 10 * (page - 1)`. Each row drops `authorId`, loads the author with `db.user.findFirst`, and attaches `sanitizeUser(author)` (utils.ts lines 50–51, which omits `password` and `iat`). It returns `{ data, meta: { page, total, totalPages } }`. The interceptor returns that object as `discussionsQuery.data`.

13. **Re-render.** `DiscussionsList` (lines 37–44) reads `discussionsQuery.data?.data` and passes it to `Table` (`src/components/ui/table/table.tsx`, lines 138–177). `Table` maps `data` to `TableRow`s. The Title column has no custom `Cell`, so the cell is `` `${entry[field]}` `` (line 166) — the new discussion's `title`.

### What a non-ADMIN sees

A signed-in user whose `user.data.role` is `'USER'` (`src/types/api.ts` types `role` as `'ADMIN' | 'USER'`) still gets the discussions page and the table (Title, Created At, View). They do not get the "Create Discussion" button, the drawer, or the form. `Authorization` is called with no `forbiddenFallback`, so the default is `null` (`authorization.tsx` line 66). `checkAccess({ allowedRoles: ['ADMIN'] })` returns false because `'ADMIN'` is not `includes`d in the user's role, `canAccess` stays false, and line 81 renders `forbiddenFallback` instead of `children`.

The same construct hides each row's delete control: `DeleteDiscussion` (`src/features/discussions/components/delete-discussion.tsx`, line 28) also wraps its button in `<Authorization allowedRoles={[ROLES.ADMIN]}>`, so those cells are empty. View links are not wrapped, so they stay.

The mechanism is the `Authorization` component in `src/lib/authorization.tsx`: `canAccess ? children : forbiddenFallback`, with `canAccess` set by `checkAccess`'s `allowedRoles.includes(user.data.role)`. (A separate server-side gate, `requireAdmin` in `src/testing/mocks/utils.ts` lines 106–110, would reject a POST from a non-admin with 500 and message `Unauthorized`, but that is not what changes this screen — the button is never rendered.)

## 2. Why `npx vitest run` fails on a fresh checkout

**Error** (thrown at `src/config/env.ts` line 28, from `createEnv` during module init at line 41):

```text
Error: Invalid env provided.
The following variables are missing or invalid:
- API_URL: Required
```

Zod 3's `z.string()` reports a missing key as `Required`. `parsedEnv.error.flatten().fieldErrors` is `{ API_URL: ['Required'] }`, and the template at lines 28–35 prints `- API_URL: Required`. `ENABLE_API_MOCKING`, `APP_URL`, and `APP_MOCK_API_PORT` are optional (the last two have defaults), so they do not fail.

**Cause.** `apps/react-vite` tracks `.env.example` and does not track `.env`. Vite reads `.env` / `.env.local`, not `.env.example`, so `import.meta.env` has no `VITE_APP_*` keys. `export const env = createEnv()` runs at import time and `EnvSchema.safeParse` fails because `API_URL` is required.

Every unit test hits that import. `vite.config.ts` (line 20) sets `setupFiles: './src/testing/setup-tests.ts'` and excludes `e2e` (line 21). There are 12 test files under `src/**/__tests__`. `setup-tests.ts` (line 4) imports `src/testing/mocks/server.ts`, which imports `src/testing/mocks/handlers/index.ts` (line 3: `import { env } from '@/config/env'`). Evaluating `env.ts` throws before any test body runs, so all 12 files fail with the same error.

**One-line fix** (run in `apps/react-vite`):

```sh
cp .env.example .env
```

`.env.example` sets `VITE_APP_API_URL=https://api.bulletproofapp.com` and `VITE_APP_ENABLE_API_MOCKING=true`, which `createEnv` accepts.

## 3. What `db.discussion.findMany` actually queries

There is no real database. `db` is an in-memory `@mswjs/data` database:

```39:39:apps/react-vite/src/testing/mocks/db.ts
export const db = factory(models);
```

`findMany` / `count` / `create` / `findFirst` run against that process-local collection. The handler in `src/testing/mocks/handlers/discussions.ts` (lines 42–51) filters it with `where: { teamId: { equals: user?.teamId } }`, `take: 10`, `skip: 10 * (page - 1)`.

**Shape** is the `models` object in `src/testing/mocks/db.ts` (lines 4–37). The `discussion` model (lines 22–29) is:

- `id`: `primaryKey(nanoid)`
- `title`: `String`
- `body`: `String`
- `authorId`: `String`
- `teamId`: `String`
- `createdAt`: `Date.now`

**Persistence across reloads in local dev** is `window.localStorage` key `msw-db`, not a server.

- After a write, the POST handler calls `persistDb('discussion')` (`discussions.ts` line 148).
- `persistDb` (`db.ts` lines 80–85) returns immediately when `process.env.NODE_ENV === 'test'`. Otherwise it `loadDb()`s, sets `data[model] = db[model].getAll()`, and `storeDb(JSON.stringify(data))`.
- In the browser, `storeDb` (lines 74–77) does `window.localStorage.setItem('msw-db', data)`.
- On the next load, `main.tsx` → `enableMocking` → `initializeDb` (`db.ts` lines 87–97) → `loadDb`. The browser branch (lines 64–66) is `JSON.parse(window.localStorage.getItem('msw-db') || '{}')`, and `initializeDb` calls `model.create(entry)` for each saved row so the factory is repopulated.

(In Node, `loadDb` / `storeDb` use a file `mocked-db.json`. That path is not what a browser reload in `dev` uses, and tests skip `persistDb`.)

## 4. Automatic redirect in `src/lib/api-client.ts`

HTTP **401** (`error.response?.status === 401`, lines 33–38).

It sets `window.location.href` to `paths.auth.login.getHref(redirectTo)`. That helper (`src/config/paths.ts`, lines 13–16) returns:

```text
/auth/login?redirectTo=${encodeURIComponent(redirectTo)}
```

when `redirectTo` is truthy. The query parameter name is **`redirectTo`**.

The value is `window.location.pathname`. Lines 34–36 build `const searchParams = new URLSearchParams()` with no input, so `searchParams.get('redirectTo')` is always `null`, and `redirectTo` falls through to `window.location.pathname`. From the discussions list that is `/app/discussions`, and the location becomes `/auth/login?redirectTo=%2Fapp%2Fdiscussions`. This is a full page navigation (`window.location.href`), not a React Router `<Navigate>`.

## 5. `VITE_APP_API_URL` → `env.API_URL`

The function is **`createEnv`** in **`src/config/env.ts`** (lines 3–39). The app reads the result via `export const env = createEnv()` (line 41).

The transformation is the `reduce` over `Object.entries(import.meta.env)` (lines 15–23):

- Keep a key only if `key.startsWith('VITE_APP_')`.
- Store it under `key.replace('VITE_APP_', '')`, which strips the first occurrence of the prefix.
- Copy the value unchanged.

So `VITE_APP_API_URL` becomes the object key `API_URL`. `EnvSchema` then requires `API_URL: z.string()` (line 5). The same rule maps `VITE_APP_ENABLE_API_MOCKING` to `ENABLE_API_MOCKING` (then the schema transforms `'true'`/`'false'` into a boolean). Keys without the `VITE_APP_` prefix are dropped.
