# Answers

## 1. Admin create flow and the non-admin view

When the discussions page is opened, the relevant sequence is:

1. `src/app/router.tsx:createAppRouter` registers `paths.app.discussions.path` as a lazy route. Its `convert` helper turns the route module's `clientLoader` into the router loader.
2. `src/app/routes/app/discussions/discussions.tsx:clientLoader` reads the `page` query parameter, builds `getDiscussionsQueryOptions({ page })`, and either reads that query from the `QueryClient` or calls `queryClient.fetchQuery(query)`.
3. `src/features/discussions/api/get-discussions.ts:getDiscussionsQueryOptions` supplies the `['discussions', { page }]` key and `getDiscussions(page)` as its query function. `getDiscussions` calls `api.get('/discussions', { params: { page } })`.
4. The MSW `http.get` handler in `src/testing/mocks/handlers/discussions.ts` checks `requireAuth(cookies)`, counts and fetches the current user's team's discussions with `db.discussion.count` and `db.discussion.findMany`, adds sanitized authors, and returns `{ data, meta }`.
5. `src/app/routes/app/discussions/discussions.tsx:DiscussionsRoute` renders `CreateDiscussion` above `DiscussionsList`. `DiscussionsList` in `src/features/discussions/components/discussions-list.tsx` calls `useDiscussions`, then passes the returned `data` to `Table`.
6. For an admin, `src/features/discussions/components/create-discussion.tsx:CreateDiscussion` renders a `FormDrawer` because its `Authorization` allows `ROLES.ADMIN`. Its trigger is a `Button` whose text is `Create Discussion`. `Button` is implemented in `src/components/ui/button/button.tsx:Button`; `FormDrawer` uses Radix's `DrawerTrigger` in `src/components/ui/form/form-drawer.tsx`.
7. Clicking the trigger causes `FormDrawer`'s `Drawer.onOpenChange` callback to call `open()` from `src/hooks/use-disclosure.ts:useDisclosure`, setting `isOpen` to `true` and displaying the drawer.
8. The drawer contains the `Form` with id `create-discussion`. `src/components/ui/form/form.tsx:Form` creates the React Hook Form instance with `zodResolver(schema)` and wires the DOM form's `onSubmit` to `form.handleSubmit(onSubmit)`. The `Input` and `Textarea` in `CreateDiscussion` register `title` and `body`; `createDiscussionInputSchema` in `src/features/discussions/api/create-discussion.ts` requires both to be non-empty.
9. The drawer's `Submit` button is a submit button with `form="create-discussion"`. Successful validation invokes `CreateDiscussion`'s `onSubmit` callback, which calls `createDiscussionMutation.mutate({ data: values })`.
10. That mutation is created by `src/features/discussions/api/create-discussion.ts:useCreateDiscussion`. Its `mutationFn` is `createDiscussion`, which calls `api.post('/discussions', data)`.
11. The Axios request interceptor `authRequestInterceptor` in `src/lib/api-client.ts` sets `Accept: application/json` and `withCredentials = true`. MSW dispatches the request to the `http.post` handler at `src/testing/mocks/handlers/discussions.ts:133`.
12. That handler calls `requireAuth`, parses the request body, calls `requireAdmin(user)` from `src/testing/mocks/utils.ts`, then calls `db.discussion.create({ teamId: user?.teamId, authorId: user?.id, ...data })`. It calls `persistDb('discussion')` and returns the created discussion as JSON.
13. On mutation success, `useCreateDiscussion`'s `onSuccess` invalidates `getDiscussionsQueryOptions().queryKey`, which is the `['discussions']` prefix. That invalidates the page query used by `DiscussionsList`, so it refetches. `CreateDiscussion`'s supplied success callback also adds the `Discussion Created` notification.
14. `FormDrawer`'s `useEffect` observes `isDone={createDiscussionMutation.isSuccess}` and calls `close()` from `useDisclosure`, removing the drawer. When the invalidated query returns, `DiscussionsList` receives the new array and re-renders `Table`; the new discussion is visible as a row.

A non-`ADMIN` user still gets the discussions route and list, but does not get the `Create Discussion` button, drawer, or form. The difference is caused by the `Authorization` wrapper at `src/features/discussions/components/create-discussion.tsx:27`:

```tsx
<Authorization allowedRoles={[ROLES.ADMIN]}>
```

`src/lib/authorization.tsx:Authorization` calls `useAuthorization().checkAccess`; `checkAccess` returns `allowedRoles.includes(user.data.role)`. For a non-admin this is false, and `Authorization` renders its default `forbiddenFallback`, which is `null` (`src/lib/authorization.tsx:63-81`). The surrounding `DiscussionsRoute` and `DiscussionsList` are not role-gated, so the list remains.

## 2. Vitest failure on a fresh checkout

All 12 suites fail during collection with the same error:

```text
Error: Invalid env provided.
The following variables are missing or invalid:
- API_URL: Required
```

The cause is `src/config/env.ts:createEnv`: its Zod schema requires `API_URL`, while the reducer only creates that key from an `import.meta.env` variable whose name starts with `VITE_APP_`. A fresh checkout has no `.env`, so `VITE_APP_API_URL` is absent. The imported MSW handlers (`src/testing/mocks/handlers/index.ts`) import `env`, causing `createEnv()` to throw before tests run.

The exact one-line fix, from `apps/react-vite`, is:

```sh
cp .env.example .env
```

That supplies the existing `VITE_APP_API_URL` line from `.env.example`. Equivalently, for a one-off test command, `VITE_APP_API_URL=https://api.bulletproofapp.com npx vitest run` makes all 12 suites pass.

## 3. What the MSW `db` queries

There is no real database. `src/testing/mocks/db.ts` imports `factory` and `primaryKey` from `@mswjs/data` and creates `export const db = factory(models)`. Therefore `db.discussion.findMany(...)` queries the in-memory `@mswjs/data` model collection held by that factory.

The model shape is defined by the `models` object in the same file. The `discussion` model has primary-key `id`, string fields `title`, `body`, `authorId`, and `teamId`, and a `createdAt` field initialized with `Date.now()`; the other models (`user`, `team`, and `comment`) are defined alongside it.

In browser local development, `loadDb` reads the serialized database from `window.localStorage.getItem('msw-db')`, and `enableMocking` in `src/testing/mocks/index.ts` calls `initializeDb`, which recreates each stored record with `model.create`. Mutating handlers call `persistDb`; in the browser it calls `storeDb`, which writes JSON back with `window.localStorage.setItem('msw-db', data)`. Thus records survive a page reload in local dev. `persistDb` returns immediately when `process.env.NODE_ENV === 'test'`, so test mutations are not persisted.

## 4. API-client redirect

The rejected-response interceptor in `src/lib/api-client.ts` redirects when `error.response?.status === 401`. It sets `window.location.href` to `paths.auth.login.getHref(redirectTo)`, i.e. `/auth/login?redirectTo=<encoded-current-path>`.

`redirectTo` is taken from a newly created `URLSearchParams` (so it is normally absent here) or falls back to `window.location.pathname`. `src/config/paths.ts:auth.login.getHref` applies `encodeURIComponent` to that path before attaching it as the `redirectTo` query parameter.

## 5. Environment-variable transformation

The exact function is `createEnv` in `apps/react-vite/src/config/env.ts`. It iterates over `Object.entries(import.meta.env)` and, for each key satisfying `key.startsWith('VITE_APP_')`, assigns:

```ts
acc[key.replace('VITE_APP_', '')] = value;
```

Consequently `VITE_APP_API_URL` becomes the `API_URL` property, which is then validated by `EnvSchema` and exposed to the application as `env.API_URL`.
