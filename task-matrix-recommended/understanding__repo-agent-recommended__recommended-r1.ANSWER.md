# Answers

## 1. `GET /api/v1/items/`

For the browser path, `frontend/src/routes/_layout/items.tsx` calls
`getItemsQueryOptions`, whose `queryFn` calls the generated
`ItemsService.readItems` method. That method is in
`frontend/src/client/sdk.gen.ts` (lines 287–300) and issues an authenticated
`GET /api/v1/items/` with `skip=0` and `limit=100`. The generated client method
name comes from the OpenAPI operation ID; the frontend route then renders the
returned `ItemsPublic.data` in `ItemsTableContent`.

On the server, `backend/app/main.py` creates `app` and includes
`api_router` with `settings.API_V1_STR` as its prefix. `backend/app/api/main.py`
builds that router and includes `items.router`, whose prefix is `/items` and
whose tag is `items` (`backend/app/api/routes/items.py:10`). Thus the route
registered by `read_items` at lines 13–15 is `/api/v1/items/`.

Before `read_items` runs, FastAPI resolves its dependencies:

1. `SessionDep` invokes `backend/app/api/deps.py:get_db`, which opens a
   `sqlmodel.Session(engine)` and yields it.
2. `CurrentUser` invokes `backend/app/api/deps.py:get_current_user`. It
   decodes the bearer token with `jwt.decode` using `settings.SECRET_KEY` and
   `security.ALGORITHM`, validates it as `TokenPayload`, then
   `session.get(User, token_data.sub)`. It rejects an invalid token (403), a
   missing user (404), or an inactive user (400), and returns the active
   `User`.

`backend/app/api/routes/items.py:read_items` then branches on
`current_user.is_superuser`:

- For a superuser, it counts all rows with `select(func.count()).select_from(Item)`,
  then selects all `Item` rows ordered by `created_at` descending, applying
  `skip` and `limit`.
- For a non-superuser, it counts only rows where
  `Item.owner_id == current_user.id`, and selects only those same owned rows,
  with the same descending ordering and pagination.

Finally, `read_items` converts each row with `ItemPublic.model_validate` and
returns `ItemsPublic(data=items_public, count=count)`. `ItemPublic` and
`ItemsPublic` are defined in `backend/app/models.py:103–112`; the response
therefore exposes each item's `id`, `title`, `description`, `owner_id`, and
`created_at`, plus the matching count.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14–15` defines:

```python
def custom_generate_unique_id(route: APIRoute) -> str:
    return f"{route.tags[0]}-{route.name}"
```

`FastAPI(..., generate_unique_id_function=custom_generate_unique_id)` at line
24 makes the operation ID consist of the first route tag, a hyphen, and the
Python function name. For the item routes this produces IDs such as
`items-read_items`, `items-create_item`, and `items-read_item`; the checked-in
OpenAPI document shows these at `docs/api/openapi.json:731, 788, 835`.

The client generator configuration in `frontend/openapi-ts.config.ts` uses
the `byTags` SDK strategy and strips the tag prefix with
`name.replace(/^[^-]*-/, "")`. Consequently the current generated methods are
`ItemsService.readItems`, `createItem`, `readItem`, `updateItem`, and
`deleteItem`.

If the custom generator were removed, FastAPI's default operation IDs would
include the route function, path, and HTTP method (for example
`read_items_items_get`, `create_item_items_post`,
`read_item_items__id__get`, `update_item_items__id__put`, and
`delete_item_items__id__delete`). The generated TypeScript SDK methods would
therefore look like `readItemsItemsGet`, `createItemItemsPost`,
`readItemItemsIdGet`, `updateItemItemsIdPut`, and `deleteItemItemsIdDelete`
(under the `ItemsService` tag grouping), rather than the short current names.

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:97–99`, on `Item.owner_id`, and the
corresponding database migration is
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22–26`.
Removing it from the model (and applying the resulting schema change) removes
the PostgreSQL foreign-key action that automatically deletes an item's row
when its `user` row is deleted. A direct database/user deletion that does not
first delete the items would then fail because `owner_id` is non-null and the
foreign key still prevents leaving child rows behind; items would not be
cascaded at the database level.

There is no existing test function that catches that FK-only regression. In
particular, `backend/app/api/routes/users.py:214–231` explicitly executes
`DELETE FROM item WHERE owner_id = user_id` at lines 228–229 before deleting
the user, so the superuser deletion path does not rely on the FK cascade. The
closest existing test is `backend/tests/api/routes/test_users.py:test_delete_user_super_user`,
but it creates no item and asserts only that the user is gone. Likewise,
`test_delete_user_me` creates no item. A test that created an owned item,
deleted the user through a path relying on the database cascade, and asserted
the item was gone would be needed to catch removal of `ondelete`.

## 4. Why verify `DUMMY_HASH`

`backend/app/crud.py:45–51` calls `verify_password(password, DUMMY_HASH)` when
`get_user_by_email` finds no user, then returns `None`. `DUMMY_HASH` at lines
40–42 is a fixed Argon2 hash. `verify_password` in
`backend/app/core/security.py:29–32` performs the same expensive password-hash
verification operation used for a real user. Running it for nonexistent
emails keeps the response timing approximately the same for “unknown email”
and “known email with a bad password,” reducing email/account enumeration via
timing attacks. The result is intentionally ignored because there is no user
to authenticate.

## 5. Item read ownership guard

The exact guard is `backend/app/api/routes/items.py:53–58` inside
`read_item`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

The `CurrentUser` dependency on line 49 (defined in
`backend/app/api/deps.py:30–49`) supplies the authenticated user. The boolean
pattern `not current_user.is_superuser and item.owner_id != current_user.id`
allows superusers through but returns HTTP 403 for a non-superuser whose ID
does not match the item's `owner_id`; this behavior is asserted by
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`.
