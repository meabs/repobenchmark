# Answers

## 1. `GET /api/v1/items/`

For the browser path, `frontend/src/routes/_layout/items.tsx:12-17`,
`getItemsQueryOptions()` calls `ItemsService.readItems(...)`. That generated
method is in `frontend/src/client/sdk.gen.ts:287-300`; it sends an authenticated
`GET` to `/api/v1/items/` through the generated client.

On the backend, the call is assembled in this order:

1. `backend/app/main.py:21-25` creates the FastAPI `app` and installs
   `custom_generate_unique_id`; `backend/app/main.py:35` includes `api_router`
   under `settings.API_V1_STR`, which is `/api/v1` in
   `backend/app/core/config.py:22`.
2. `backend/app/api/main.py:10` includes `items.router`.
   `backend/app/api/routes/items.py:10` defines that router with prefix
   `/items` and tag `items`, and `:13-16` registers `read_items` for `GET /`.
3. Before `read_items` runs, its `SessionDep` is resolved by
   `backend/app/api/deps.py:get_db` (`:21-24`), which opens a SQLModel
   `Session(engine)` from `backend/app/core/db.py`. Its `CurrentUser` is
   resolved by `get_current_user` in `backend/app/api/deps.py:30-46`: it
   decodes the bearer JWT with `jwt.decode`, validates `TokenPayload`, loads
   the `User` with `session.get(User, token_data.sub)`, and rejects invalid,
   missing, or inactive users.
4. `backend/app/api/routes/items.py:14-45`, `read_items`, branches on
   `current_user.is_superuser`.
5. The returned `Item` objects are converted with
   `ItemPublic.model_validate` at `items.py:44`, then wrapped as
   `ItemsPublic(data=items_public, count=count)` at `:45`; FastAPI serializes
   that response according to `response_model=ItemsPublic`.

For a superuser (`items.py:21-27`), `count` is `COUNT(*)` over all `Item`
rows, and the item query selects all items, orders by
`Item.created_at DESC`, and applies `skip` and `limit`.

For a non-superuser (`items.py:28-42`), both the count query and item query
add `WHERE Item.owner_id == current_user.id`. They therefore see/count only
their own items; the same descending `created_at` ordering and pagination are
then applied.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns
`f"{route.tags[0]}-{route.name}"`. The FastAPI app passes it as
`generate_unique_id_function` at `main.py:24`, so the items operations get IDs
such as `items-read_items`, `items-read_item`, `items-create_item`,
`items-update_item`, and `items-delete_item`. The frontend generator is
configured in `frontend/openapi-ts.config.ts:11-18` to group by tags, make
static service methods, and strip everything through the first hyphen. That
produces `ItemsService.readItems`, `readItem`, `createItem`, `updateItem`, and
`deleteItem` in `frontend/src/client/sdk.gen.ts`.

If the custom function were removed, FastAPI's default generator in the
installed version constructs `route.name + route.path_format`, replaces
non-word characters with `_`, and appends the lowercase HTTP method. Thus the
items operation IDs would be:

| route function | default operation ID | generated method |
|---|---|---|
| `read_items` | `read_items_api_v1_items__get` | `readItemsApiV1ItemsGet` |
| `read_item` | `read_item_api_v1_items__id__get` | `readItemApiV1ItemsIdGet` |
| `create_item` | `create_item_api_v1_items__post` | `createItemApiV1ItemsPost` |
| `update_item` | `update_item_api_v1_items__id__put` | `updateItemApiV1ItemsIdPut` |
| `delete_item` | `delete_item_api_v1_items__id__delete` | `deleteItemApiV1ItemsIdDelete` |

They would still be grouped under `ItemsService`, but existing callers such as
`frontend/src/routes/_layout/items.tsx:15` would need the renamed methods.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-100` declares `Item.owner_id` as a non-null foreign
key to `user.id` with `ondelete="CASCADE"`. Removing that option removes the
database-level rule that deletes an owner's Items when the User row is deleted.
A direct database deletion of a User that still has Items would then be
rejected by PostgreSQL's foreign-key constraint (and could not leave an Item
with a null owner because `nullable=False`). The schema migration that adds
the rule is also explicit at
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`.

The current HTTP deletion paths partly mask this: `delete_user` in
`backend/app/api/routes/users.py:214-231` explicitly deletes matching Items at
`:228-229`, and `delete_user_me` at `:141-142` deletes the ORM User while the
User relationship in `models.py:59` has `cascade_delete=True`.

There is no existing test function that actually catches removal of the
database `ondelete` rule. `backend/tests/api/routes/test_users.py` functions
`test_delete_user_me` and `test_delete_user_super_user` verify User deletion,
but neither creates an Item owned by the User being deleted; the latter route
also explicitly deletes Items. A regression test would need to create an owned
Item, delete its User through a path that relies on the database FK, and assert
the Item is gone (or that deletion fails without the cascade).

## 4. `DUMMY_HASH`

`backend/app/crud.py:45-60`, `authenticate`, calls
`get_user_by_email` and, when no user is found, runs
`verify_password(password, DUMMY_HASH)` at `:50` before returning `None`.
`verify_password` delegates to Argon2/bcrypt verification in
`backend/app/core/security.py:29-32`. The deliberately expensive hash work
makes the nonexistent-email path take approximately the same time as the
existing-user path, preventing an attacker from timing the login endpoint
(`backend/app/api/routes/login.py:23-35`) to enumerate registered email
addresses. The result is discarded because there is no real account to
authenticate.

## 5. Reading an individual Item

The exact access-control pattern is in
`backend/app/api/routes/items.py:48-58`, function `read_item`: it first loads
the row with `session.get(Item, id)` at `:53`, returns 404 if absent at
`:54-55`, then checks:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

`current_user` is supplied by the `CurrentUser` dependency from
`backend/app/api/deps.py:49`, whose `get_current_user` implementation is at
`:30-46`. Therefore superusers bypass the owner comparison, while a
non-superuser can read only an Item whose `owner_id` equals that user's ID.
The existing regression test for this exact behavior is
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`
(`:55-65`).
