# Answers

## 1. Admin discussion creation flow

When the signed-in user opens /app/discussions, the route is loaded by createAppRouter in apps/react-vite/src/app/router.tsx:24-80. Its lazy route conversion invokes the route's clientLoader from apps/react-vite/src/app/routes/app/discussions/discussions.tsx:10-23. clientLoader reads the page search parameter, obtains getDiscussionsQueryOptions({ page }), and fetches it through the query client if it is not already cached. The route component DiscussionsRoute at .../discussions.tsx:25-44 renders CreateDiscussion and DiscussionsList as siblings.

The click-and-submit sequence is:

1. CreateDiscussion in apps/react-vite/src/features/discussions/components/create-discussion.tsx:13-73 builds a FormDrawer. Its triggerButton is the Button labelled “Create Discussion” (:30-34). FormDrawer in apps/react-vite/src/components/ui/form/form-drawer.tsx:24-69 passes that button to DrawerTrigger; clicking it changes the useDisclosure state via onOpenChange (:40-48), making the drawer and its form visible.

2. The drawer's Form has id create-discussion and uses createDiscussionInputSchema (create-discussion.tsx:47-53). The shared Form implementation in apps/react-vite/src/components/ui/form/form.tsx:182-205 creates the React Hook Form instance with zodResolver(schema) (:193), and submits through form.handleSubmit(onSubmit) (:196-199). The Input and Textarea are registered as title and body (create-discussion.tsx:54-66); the schema in apps/react-vite/src/features/discussions/api/create-discussion.ts:10-13 requires both to be nonempty strings.

3. On valid submit, the onSubmit callback in create-discussion.tsx:49-51 calls createDiscussionMutation.mutate({ data: values }). That mutation was created by useCreateDiscussion (create-discussion.ts:29-45), whose mutationFn is createDiscussion (:44). createDiscussion calls api.post('/discussions', data) (create-discussion.ts:17-23). The Axios request interceptor in apps/react-vite/src/lib/api-client.ts:6-14 adds Accept: application/json and withCredentials = true.

4. With API mocking enabled, MSW matches the http.post handler in apps/react-vite/src/testing/mocks/handlers/discussions.ts:133-156. requireAuth (:137-140, implemented in apps/react-vite/src/testing/mocks/utils.ts:80-104) resolves the cookie to a user; requireAdmin(user) (discussions.ts:142, implemented at utils.ts:106-110) enforces the role. The handler parses the request body, calls db.discussion.create with teamId, authorId, title, and body (discussions.ts:141-147), persists the discussion with persistDb('discussion') (:148), and returns the created object (:149).

5. Axios's successful response interceptor in apps/react-vite/src/lib/api-client.ts:17-20 returns response.data, so the mutation resolves. Its onSuccess wrapper in useCreateDiscussion (create-discussion.ts:36-45) first calls queryClient.invalidateQueries({ queryKey: getDiscussionsQueryOptions().queryKey }) (:37-41). The active discussions query is therefore refetched through getDiscussions in apps/react-vite/src/features/discussions/api/get-discussions.ts:7-18, which calls api.get('/discussions', { params: { page } }).

6. The matching GET handler in handlers/discussions.ts:19-79 filters db.discussion by the signed-in user's teamId, applies pagination, and returns the rows plus metadata. DiscussionsList in apps/react-vite/src/features/discussions/components/discussions-list.tsx:19-92 receives the new query data from useDiscussions (:24-26) and re-renders Table with that data (:42-90), so the new title appears as a row. The mutation's caller-supplied success callback also adds the “Discussion Created” notification (create-discussion.tsx:15-23), and FormDrawer sees isDone={createDiscussionMutation.isSuccess} and closes itself in its effect (form-drawer.tsx:33-37).

For a non-ADMIN user, DiscussionsRoute still renders DiscussionsList, so the discussion rows remain visible, but CreateDiscussion renders no button, drawer, or form. The exact cause is the Authorization wrapper at create-discussion.tsx:26-71 with allowedRoles={[ROLES.ADMIN]}. In apps/react-vite/src/lib/authorization.tsx:63-81, Authorization calls useAuthorization().checkAccess; checkAccess returns allowedRoles.includes(user.data.role) (:35-46). Its default forbiddenFallback is null (:63-68), and the component returns the children only when canAccess is true (:71-81). Thus a USER sees the list but no create control. The row-level delete control is likewise absent because DeleteDiscussion has the same ADMIN-only Authorization wrapper (apps/react-vite/src/features/discussions/components/delete-discussion.tsx:28-49). The server independently rejects a non-admin POST through requireAdmin in handlers/discussions.ts:142, but the UI wrapper is what makes the control disappear.

## 2. Fresh-checkout Vitest failure

The repeated collection-time error is:

    Error: Invalid env provided.
    The following variables are missing or invalid:
    - API_URL: Required

The top-level createEnv() call in apps/react-vite/src/config/env.ts:3-41 reads import.meta.env, extracts only VITE_APP_ variables, and validates the resulting object against a schema that requires API_URL (:4-5). A fresh checkout has apps/react-vite/.env.example but no .env; Vite does not load .env.example, so VITE_APP_API_URL is absent and all test files fail with the same import-time validation error.

The exact one-line fix, run from apps/react-vite, is:

    cp .env.example .env

## 3. What the mock db queries

There is no real database. db is an in-memory @mswjs/data database created by factory(models) in apps/react-vite/src/testing/mocks/db.ts:1-2,39. Therefore db.discussion.findMany(...) in apps/react-vite/src/testing/mocks/handlers/discussions.ts:42-51 queries the in-process discussion model collection maintained by that factory. Its shape is the models object in db.ts:4-37: each discussion has a generated primary key id, string title, string body, string authorId, string teamId, and createdAt initialized from Date.now() (:22-29).

In local browser development, persistDb('discussion') in the POST handler (handlers/discussions.ts:143-149) calls persistDb in db.ts:80-85, which stores the model's getAll() result under the msw-db key in window.localStorage (db.ts:69-78). On the next page load, enableMocking calls initializeDb (apps/react-vite/src/testing/mocks/index.ts:3-9), which loads localStorage['msw-db'] through loadDb (db.ts:63-67) and recreates each stored entity with model.create (db.ts:87-97). Node-based execution has a separate mocked-db.json path (db.ts:43-61), but local dev in the browser uses localStorage.

## 4. Automatic API-client redirect

The rejected-response interceptor in apps/react-vite/src/lib/api-client.ts:17-35 redirects when error.response?.status === 401 (:27). It computes redirectTo as the current window.location.pathname because its new, empty URLSearchParams has no value (:28-30), then assigns window.location.href = paths.auth.login.getHref(redirectTo) (:31). paths.auth.login.getHref in apps/react-vite/src/config/paths.ts:13-17 produces /auth/login?redirectTo=<encoded-path>, so the attached query parameter is redirectTo.

## 5. Env-var transformation

The function is createEnv in apps/react-vite/src/config/env.ts:3-41, and it exports the validated result as env at :41. Its reduction over Object.entries(import.meta.env) (:15-23) keeps keys beginning with VITE_APP_ (:19) and assigns acc[key.replace('VITE_APP_', '')] = value (:20). Thus VITE_APP_API_URL=https://... becomes { API_URL: 'https://...' }, which the rest of the app reads as env.API_URL; the same prefix-stripping rule applies to the other VITE_APP_ variables.

