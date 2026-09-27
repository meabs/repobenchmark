# Answers

## 1. `GET /api/v1/items/`

The application and routing path is:

1. `backend/app/main.py:21-25` constructs the `FastAPI` app and installs
   `generate_unique_id_function=custom_generate_unique_id`; line 35 mounts
   `api_router` under `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py:6-10` builds `api_router` and includes
   `items.router`.
3. `backend/app/api/routes/items.py:10` declares the router with prefix
   `/items` and tag `items`. Its `@router.get("/", response_model=ItemsPublic)`
   at lines 13-16 registers `read_items` for the resulting path
   `/api/v1/items/`.
4. Before `read_items` runs, FastAPI resolves `SessionDep` and `CurrentUser`
   from `backend/app/api/deps.py`. `SessionDep` (lines 21-26) calls `get_db`,
   which opens `Session(engine)` and yields it. `CurrentUser` (line 49) calls
   `get_current_user` (lines 30-46): it decodes the bearer token with
   `jwt.decode` using `settings.SECRET_KEY` and `security.ALGORITHM`, validates
   `TokenPayload`, loads the UUID in `session.get(User, token_data.sub)`, and
   rejects an invalid token, missing user, or inactive user.
5. FastAPI calls `backend/app/api/routes/items.py:14-45`, `read_items`, with
   `skip` and `limit` query parameters (defaults 0 and 100).
6. If `current_user.is_superuser` is true, lines 21-27 count all `Item` rows
   and select all items, ordered by `Item.created_at` descending, then apply
   offset and limit. No owner predicate is added.
7. Otherwise, lines 29-42 count and select only rows satisfying
   `Item.owner_id == current_user.id`; the same descending order and pagination
   are applied.
8. Lines 44-45 convert each ORM `Item` to `ItemPublic` with
   `ItemPublic.model_validate(item)` and return `ItemsPublic(data=..., count=...)`.
   `ItemPublic` is defined in `backend/app/models.py:103-107`, and
   `ItemsPublic` at lines 110-112. FastAPI validates/serializes that declared
   response model before sending JSON.

Thus a superuser receives a paginated view of every item and a total count of
every item; a non-superuser receives only their own items and a count of only
those items. Both views are newest-first and use the same `skip`/`limit`.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. For the
items router this produces operation IDs such as `items-read_items`,
`items-create_item`, and `items-read_item`. The function is passed to FastAPI at
`backend/app/main.py:24`; the committed schema confirms these IDs, for example
`items-read_items` at `docs/api/openapi.json:731`.

The generated client turns those short IDs into readable names: the current
`frontend/src/client/sdk.gen.ts:287-365` exposes `ItemsService.readItems`,
`createItem`, `readItem`, `updateItem`, and `deleteItem`. If the custom function
were removed, FastAPI would use its default path/method-derived IDs, so the
client names would include the resource path and HTTP method, e.g.
`readItemsItemsGet`, `createItemItemsPost`, `readItemItemsIdGet`,
`updateItemItemsIdPut`, and `deleteItemItemsIdDelete` (with the exact number of
underscores depending on the generator's normalization of the trailing slash).
That is the verbose naming the decision record refers to:
`docs/ard/0005-generated-typescript-client.md:23-25`.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-100` currently defines `Item.owner_id` as a
non-nullable foreign key to `user.id` with database-level `ondelete="CASCADE"`.
Removing that argument would remove the database FK action (after the matching
Alembic schema change): deleting a `User` directly at the database level would
no longer automatically delete its `Item` rows, and a delete could instead
fail with a foreign-key violation while dependent rows remain.

The migration that introduced this behavior is
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-27`.
The ORM relationship `User.items = Relationship(..., cascade_delete=True)` at
`backend/app/models.py:59` is a separate ORM-level cascade. Also, the two user
deletion routes currently avoid relying solely on the database action:
`delete_user_me` calls `session.delete(current_user)` at
`backend/app/api/routes/users.py:132-143`, and the superuser deletion route
explicitly executes `delete(Item).where(Item.owner_id == user_id)` at
`backend/app/api/routes/users.py:214-231`.

There is no existing test function in this checkout that catches removal of the
database FK action. `backend/tests/api/routes/test_users.py:test_delete_user_me`
only verifies that the user row disappears (lines 420-449); it creates no Item
and does not assert dependent-item deletion. `test_delete_user_super_user`
(same file, lines 463-480) explicitly deletes the Items in the route before
deleting the user, so it also cannot catch a missing FK cascade. A regression
test would need to create a user and owned item, delete the user without the
route's explicit item deletion, and assert the item is gone.

## 4. `DUMMY_HASH`

`backend/app/crud.py:45-60` calls `get_user_by_email` first. When no user is
found, lines 47-51 still call `verify_password(password, DUMMY_HASH)` and then
return `None`. `DUMMY_HASH` at lines 40-42 is a fixed Argon2 hash.

Password verification is deliberately expensive. Performing the same hash
verification for nonexistent accounts makes an unknown-email login take roughly
the same time as a wrong-password login for an existing account, preventing
response timing from revealing which email addresses are registered. This is
the timing-attack mitigation documented in `docs/ard/0002-jwt-bearer-auth.md:26-27`.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the inline ownership guard in
`backend/app/api/routes/items.py`, function `read_item`, lines 48-58:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

`read_item` first loads the row with `session.get(Item, id)` and returns 404 if
missing (lines 53-55). For an existing row, the condition denies a non-owner
with HTTP 403; the `not current_user.is_superuser` part exempts superusers.
This is application-enforced authorization, not a PostgreSQL row-level policy,
as also noted in `okf/routers/items.md` and `okf/tables/item.md`.
