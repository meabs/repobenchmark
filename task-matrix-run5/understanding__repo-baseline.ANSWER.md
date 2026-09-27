# Answers

## 1. `GET /api/v1/items/`

The browser path starts in `frontend/src/routes/_layout/items.tsx`:

1. TanStack Router selects `Route`, whose `component` is `Items()` (line 20). `Items()` renders `ItemsTable()`, which renders `ItemsTableContent()` inside `Suspense` (lines 57-68 and 49-54).
2. `ItemsTableContent()` calls `useSuspenseQuery(getItemsQueryOptions())` (line 32). `getItemsQueryOptions()` supplies the query function at lines 12-16, which calls `ItemsService.readItems({ query: { skip: 0, limit: 100 } })`.
3. `frontend/src/client/sdk.gen.ts:293-300`, `ItemsService.readItems`, calls the generated client’s `get` method for `/api/v1/items/` and declares bearer security.
4. The generated client was configured in `frontend/src/main.tsx:17-20`: its base URL is `VITE_API_URL` (or `""`) and its auth callback reads `localStorage.access_token`. `frontend/src/client/client/utils.gen.ts:setAuthParams` and `frontend/src/client/core/auth.gen.ts:getAuthToken` turn that token into `Authorization: Bearer <token>`.
5. FastAPI mounts `api_router` under `settings.API_V1_STR` in `backend/app/main.py:21-35`. `backend/app/api/main.py:6-10` includes `items.router`; `backend/app/api/routes/items.py:10` defines that router as `/items` with tag `items`, and `read_items` handles `GET /` at lines 13-16.
6. Before `read_items` runs, `SessionDep` calls `backend/app/api/deps.py:get_db` (lines 21-23), yielding a SQLModel `Session` backed by `backend/app/core/db.py:engine`. `CurrentUser` calls `get_current_user` (deps.py:30-46): it decodes the bearer JWT with `jwt.decode`, validates `TokenPayload`, loads `User` by the token subject, rejects missing/inactive users, and returns the user.
7. `read_items` in `backend/app/api/routes/items.py:14-45` branches on `current_user.is_superuser`. A superuser counts all `Item` rows (lines 21-23), selects all items ordered by descending `created_at` with `skip`/`limit` (lines 24-27), converts them to `ItemPublic`, and returns `ItemsPublic(data=..., count=...)`. A non-superuser counts only rows where `Item.owner_id == current_user.id` (lines 28-34), selects only those rows with the same ordering/pagination (lines 35-42), and returns the same response shape. Thus superusers see every item and the global count; ordinary users see only their own items and their own count.
8. FastAPI validates the return against `ItemsPublic`/`ItemPublic` from `backend/app/models.py:103-113`, then serializes the JSON response. The frontend query receives `.data`; an empty array renders the empty state at `items.tsx:34-43`, otherwise `DataTable` receives `items.data` at line 46.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. For this route, the tag is `items` and the Python function name is `read_items`, so its OpenAPI operation ID is `items-read_items`. `generate_unique_id_function=custom_generate_unique_id` is installed on the `FastAPI` app at line 24.

The OpenAPI TypeScript generator (`frontend/openapi-ts.config.ts:11-18`) groups operations by tag and strips the tag prefix from the operation ID, producing the current `ItemsService.readItems` and `itemsReadItems*` types. If the custom function were removed, FastAPI’s default generator would use `route.name + route.path_format`, sanitize non-word characters, and append the HTTP method; for this mounted route that is `read_items_api_v1_items__get`. The generated names would consequently be path-derived/camelized names such as `ItemsService.readItemsApiV1ItemsGet` and `itemsReadItemsApiV1ItemsGetData`/`...Responses`, rather than `readItems` and `itemsReadItems...`.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-100` declares `Item.owner_id` as a non-nullable foreign key to `user.id` with database-level `ON DELETE CASCADE`; the corresponding migration is `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`. Removing it means a database-level deletion of a `User` would no longer automatically delete that user’s `Item` rows; it could fail with a foreign-key violation (or leave dependent rows, depending on the database operation/configuration). The ORM-side `User.items = Relationship(..., cascade_delete=True)` at `models.py:59` and `users.py:228-230`’s explicit item delete can mask this for the current application paths, so changing only the model also does not alter an already-migrated database until the schema is migrated.

There is no existing test function that actually catches this regression: `backend/tests/api/routes/test_users.py:test_delete_user_me` (lines 420-448) deletes a newly created user but creates no item and asserts only that the user is gone; `test_delete_user_super_user` likewise creates no item, and the admin deletion route explicitly deletes items first. The exact test that would need to exist to catch the missing cascade would create an item owned by the deleted user and assert that the item is gone. Therefore the premise that an existing test catches it is false for this checkout; the closest relevant function is `test_delete_user_me`, but it does not test the cascade.

## 4. `DUMMY_HASH`

`backend/app/crud.py:45-60` first calls `get_user_by_email`. If no user exists, it still calls `verify_password(password, DUMMY_HASH)` at lines 47-50 and returns `None`. `DUMMY_HASH` is a fixed Argon2 hash (lines 40-42), so the expensive password-hash verification takes place whether or not the email lookup found a user. Without that work, nonexistent emails would return faster than existing emails with a wrong password, enabling timing-based email/user enumeration. The result is deliberately ignored; it is only timing equalization.

## 5. Per-item ownership check

The exact mechanism is the inline authorization guard in `backend/app/api/routes/items.py:48-58`, function `read_item`. It first loads the row with `session.get(Item, id)` (line 53), returns 404 if absent (lines 54-55), then rejects a non-superuser whose `item.owner_id` differs from `current_user.id` (lines 56-57) with HTTP 403 and `"Not enough permissions"`. Only superusers bypass that ownership comparison. The regression/behavior test is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions` (lines 55-65).
