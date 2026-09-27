# Answers

## 1. `GET /api/v1/items/`

The frontend path is:

1. `frontend/src/routes/_layout/items.tsx:getItemsQueryOptions()` builds the
   TanStack Query options. Its `queryFn` calls
   `ItemsService.readItems({ query: { skip: 0, limit: 100 } })`.
2. `frontend/src/client/sdk.gen.ts:ItemsService.readItems()` calls the
   generated client's `get` method with the bearer security scheme and URL
   `/api/v1/items/`.
3. `frontend/src/client/client/client.gen.ts:createClient()` supplies that
   `get` method through `makeMethodFn("GET")`; `beforeRequest()` calls
   `setAuthParams()` and `buildUrl()`, then `request()` invokes Axios. The
   bearer token is formatted by `frontend/src/client/core/auth.gen.ts:getAuthToken()`.
4. In `backend/app/main.py`, `app` was constructed with
   `generate_unique_id_function=custom_generate_unique_id` and includes
   `api_router` with `settings.API_V1_STR` (normally `/api/v1`) as prefix.
   `backend/app/api/main.py` added `items.router` to `api_router`; that router
   has prefix `/items`, tag `items`, and its `GET "/"` handler is
   `backend/app/api/routes/items.py:read_items()`.
5. Before `read_items()` runs, FastAPI resolves `SessionDep` by calling
   `backend/app/api/deps.py:get_db()`, which yields a SQLModel `Session(engine)`,
   and resolves `CurrentUser` by calling `get_current_user()`. That function
   decodes the bearer JWT with `jwt.decode()` using `settings.SECRET_KEY` and
   `security.ALGORITHM`, validates `TokenPayload`, loads the user with
   `session.get(User, token_data.sub)`, and rejects an absent user (404) or
   inactive user (400).
6. `read_items()` branches on `current_user.is_superuser`:
   - Superuser: counts all rows with `select(func.count()).select_from(Item)`;
     selects all `Item` rows, ordered by `Item.created_at` descending, then
     applies `skip` and `limit`.
   - Non-superuser: both the count query and item query add
     `where(Item.owner_id == current_user.id)`. The item query uses the same
     descending `created_at` ordering and pagination, so other users' items are
     excluded from both `data` and `count`.
7. Each selected ORM item is converted with `ItemPublic.model_validate()` and
   returned as `ItemsPublic(data=items_public, count=count)`. FastAPI applies
   the declared `ItemsPublic` response model, and the generated client receives
   that JSON response; `ItemsTableContent()` reads `items.data` and renders it.

## 2. `custom_generate_unique_id`

`backend/app/main.py:custom_generate_unique_id(route)` returns
`f"{route.tags[0]}-{route.name}"`. For the items list route, `route.tags[0]`
is `"items"` and `route.name` is `"read_items"`, so its OpenAPI operation ID
is `items-read_items`. The `@hey-api/openapi-ts` configuration in
`frontend/openapi-ts.config.ts` groups by tags and strips the prefix through
`methodName: name => name.replace(/^[^-]*-/, "")`; consequently the generated
method is `ItemsService.readItems`.

If the custom function were removed, FastAPI's default unique ID for this
route would be `read_items_items__get` (handler name + normalized path + HTTP
method). With the existing `byTags` generator, the corresponding generated
method would therefore be `ItemsService.readItemsItemsGet` (and its generated
types would use the analogous `readItemsItemsGetData`, `...Responses`, etc.),
rather than `ItemsService.readItems`.

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:97-99`, on `Item.owner_id`. The
database-level consequence is that deleting a `user` directly in PostgreSQL
would no longer cascade to its `item` rows; because `owner_id` is non-nullable,
the foreign-key constraint would instead reject the parent delete unless the
children were deleted first. The migration that establishes this behavior is
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:25-26`.

For the application code as it currently exists, no existing test actually
asserts this specific database-level cascade. `User.items` in `models.py:59`
also has SQLAlchemy `cascade_delete=True`; `users.py:228-230` explicitly bulk
deletes owned items before the superuser delete. `test_delete_user_me()` and
`test_delete_user_super_user()` in `backend/tests/api/routes/test_users.py`
only assert that the user is gone and do not create/check an owned Item.
Therefore there is no exact existing test function that would catch removing
only `Item.owner_id.ondelete`; a regression test would need to create a user
and item, delete the user, and assert the item is gone (or exercise a direct
database parent delete).

## 4. `DUMMY_HASH`

`backend/app/crud.py:authenticate()` calls `verify_password(password,
DUMMY_HASH)` when `get_user_by_email()` returns no user, then returns `None`.
`verify_password()` delegates to Argon2/bcrypt `password_hash.verify_and_update()`
in `backend/app/core/security.py:29-32`. Performing the deliberately expensive
password-hash verification on the nonexistent-user path makes the response
time resemble the existing-user path, preventing an attacker from using timing
differences to enumerate registered email addresses. The dummy hash is a fixed
Argon2 hash of a random password and its result is intentionally ignored.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the authorization guard in
`backend/app/api/routes/items.py:56-57`, inside
`read_item(session, current_user, id)`: after `session.get(Item, id)` and the
404 check, it raises `HTTPException(status_code=403, detail="Not enough permissions")`
when `current_user.is_superuser` is false and `item.owner_id != current_user.id`.
The existing regression test is
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions()`
(lines 55-65), which creates an item owned by another random user and asserts
that the normal user's GET returns 403 with that detail.
