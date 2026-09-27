# Answers

## 1. `GET /api/v1/items/`

The frontend call begins in `frontend/src/routes/_layout/items.tsx`, in
`getItemsQueryOptions()`: its `queryFn` calls
`ItemsService.readItems({ query: { skip: 0, limit: 100 } })`. `ItemsService.readItems`
is the generated static method in `frontend/src/client/sdk.gen.ts`; it sends an
authenticated `GET` to `/api/v1/items/`. The generated client is exported by
`frontend/src/client/index.ts`. (The generated method uses the bearer security
scheme; the access-token/client configuration supplies the Authorization header.)

At application setup, `backend/app/main.py` creates `app` and includes
`api_router` at `settings.API_V1_STR` (normally `/api/v1`).
`backend/app/api/main.py` includes `items.router`. That router is declared in
`backend/app/api/routes/items.py` with prefix `/items` and tag `items`, so its
`@router.get("/")` route is the requested endpoint and dispatches to
`read_items()`.

Before `read_items()` runs, its parameters resolve the dependencies declared in
`backend/app/api/deps.py`: `SessionDep` calls `get_db()`, which opens a
`sqlmodel.Session(engine)` and yields it; `CurrentUser` calls
`get_current_user()`. `get_current_user()` decodes the bearer JWT with
`jwt.decode(..., settings.SECRET_KEY, algorithms=[security.ALGORITHM])`, builds
`TokenPayload`, loads the subject with `session.get(User, token_data.sub)`, and
rejects an invalid token (403), missing user (404), or inactive user (400).

`read_items()` then branches at `backend/app/api/routes/items.py:21`:

- For a superuser, it counts all `Item` rows with `select(func.count()).select_from(Item)`,
  then selects all items ordered by `Item.created_at` descending, applying the
  requested `skip` and `limit`.
- For a non-superuser, both the count query and item query add
  `where(Item.owner_id == current_user.id)`. Thus the count and returned rows
  include only that user’s items; ordering and pagination are otherwise the
  same.

The selected rows are converted with `ItemPublic.model_validate(item)` and
returned as `ItemsPublic(data=items_public, count=count)`. FastAPI applies the
declared `response_model=ItemsPublic` before serializing the response. In the
frontend, the query result is consumed by `ItemsTableContent()` in the same
route file and passed as `items.data` to `DataTable` (or an empty-state message
is rendered).

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines `custom_generate_unique_id(route)` as
`f"{route.tags[0]}-{route.name}"`. Because `items.router` has tag `items` and
the handler names are `read_items`, `create_item`, `delete_item`, `read_item`,
and `update_item`, the operation IDs are, for example,
`items-read_items` and `items-read_item`.

`app = FastAPI(...)` passes this function as
`generate_unique_id_function=custom_generate_unique_id`, and
`frontend/openapi-ts.config.ts:17` removes the tag prefix before generating
methods (`name.replace(/^[^-]*-/, "")`). That is why the generated class in
`frontend/src/client/sdk.gen.ts` has methods such as `ItemsService.readItems()`
and `ItemsService.readItem()`.

If that argument were removed, FastAPI 0.141.1’s default generator would use
`route.name + route.path_format`, replace non-word characters with `_`, and
append the lower-case HTTP method. For these routes the operation IDs would be
`read_items_api_v1_items__get` and `read_item_api_v1_items__id__get` (and
analogously `create_item_api_v1_items__post`, `delete_item_api_v1_items__id__delete`,
and `update_item_api_v1_items__id__put`). Since those IDs contain no hyphen for
the configured prefix-removal function to strip, the generated TypeScript
methods would be path-suffixed names such as
`readItemsApiV1ItemsGet()` and `readItemApiV1ItemsIdGet()` in `ItemsService`
(with corresponding `createItemApiV1ItemsPost`, `deleteItemApiV1ItemsIdDelete`,
and `updateItemApiV1ItemsIdPut`).

## 3. Removing `Item.owner_id`’s `ondelete="CASCADE"`

`backend/app/models.py:97-99` declares the foreign key from `item.owner_id` to
`user.id` with `ondelete="CASCADE"`. Removing it would remove the database-level
cascade from newly generated schema/migrations: deleting a user while owned
items still exist could then violate the non-null foreign key instead of
deleting those items. The already committed migration
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:25-26`
explicitly creates the `ondelete='CASCADE'` constraint, so changing only the
model does not alter an already migrated database. Also, `User.items` still
has SQLAlchemy `cascade_delete=True` at `models.py:59`, and
`backend/app/api/routes/users.py:228-230` explicitly deletes the user’s items
before deleting the user.

There is no existing test function that would catch this specific regression:
`backend/tests/api/routes/test_users.py` functions such as
`test_delete_user_me()` and `test_delete_user_super_user()` delete users but
never create/assert an owned `Item`; the item tests cover item access and direct
item deletion only. A test that creates an item for a user, deletes that user,
and asserts the item is gone would be required. Therefore no exact existing
test name can truthfully be supplied for this regression.

## 4. Why authenticate verifies `DUMMY_HASH`

In `backend/app/crud.py:45-51`, `authenticate()` first looks up the user by
email. If no user exists, it still calls `verify_password(password, DUMMY_HASH)`
before returning `None`. `DUMMY_HASH` is a fixed Argon2 hash of a random
password. `verify_password()` in `backend/app/core/security.py:29-32` performs
the deliberately expensive Argon2 verification (and possible hash-update
check). Running that work on the missing-user path makes it take roughly the
same time as the real-user/wrong-password path, preventing response timing from
revealing whether an email address exists.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the authorization guard in
`backend/app/api/routes/items.py:53-57`, inside `read_item()`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

`CurrentUser` is supplied by `get_current_user()` in
`backend/app/api/deps.py`; the condition permits a superuser, or a regular user
whose UUID equals `item.owner_id`, and returns 403 for every other owner.
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`
asserts this exact 403 behavior.
