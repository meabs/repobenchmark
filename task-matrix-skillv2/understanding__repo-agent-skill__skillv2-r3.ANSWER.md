# Answers

## 1. `GET /api/v1/items/`

The request path is:

1. `backend/app/main.py:21-25` creates the `FastAPI` app and installs
   `custom_generate_unique_id`; `backend/app/main.py:35` includes `api_router`
   under `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py:10` includes `items.router`.
   `backend/app/api/routes/items.py:10` gives that router the `/items` prefix
   and `items` tag, and `:13-16` registers `GET /` as `read_items`.
3. FastAPI resolves `SessionDep` and `CurrentUser` from
   `backend/app/api/deps.py:26` and `:49`. `SessionDep` calls `get_db` (`:21-23`),
   which opens a SQLModel `Session(engine)` and yields it. `CurrentUser` calls
   `get_current_user` (`:30-46`): it decodes the bearer JWT using
   `settings.SECRET_KEY` and `security.ALGORITHM`, loads the `User` by the JWT
   subject, and rejects an absent user (404) or inactive user (400).
4. `backend/app/api/routes/items.py:14-45`, `read_items`, branches on
   `current_user.is_superuser`.
   - Superuser: lines 21-27 count every `Item`, then select every item ordered
     by `created_at` descending, applying `skip` and `limit` (defaults 0 and
     100).
   - Non-superuser: lines 28-42 count and select only rows where
     `Item.owner_id == current_user.id`, with the same ordering and pagination.
5. Lines 44-45 validate each result as `ItemPublic` and return
   `ItemsPublic(data=items_public, count=count)`. Thus a superuser gets the
   global count/page; a normal user gets only their own count/page. The response
   is serialized under the `ItemsPublic` response model. The corresponding
   schema in `docs/api/openapi.json` has operation ID `items-read_items`.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. For this
route that is `items-read_items`; `main.py:24` passes the function to FastAPI as
`generate_unique_id_function`. The generated OpenAPI operation IDs therefore
use the tag plus endpoint name, and Hey API generates the current
`ItemsService.readItems` method (see `frontend/src/client/sdk.gen.ts:287-300`).

If the custom function were removed, FastAPI would use its default path-based
IDs. For the item routes those IDs would be:

```text
read_items_api_v1_items__get
create_item_api_v1_items__post
read_item_api_v1_items__id__get
update_item_api_v1_items__id__put
delete_item_api_v1_items__id__delete
```

The generated client would consequently expose the path-derived camel-cased
operation names (for example `ItemsService.readItemsApiV1ItemsGet` rather than
`ItemsService.readItems`, and similarly
`createItemApiV1ItemsPost`, `readItemApiV1ItemsIdGet`,
`updateItemApiV1ItemsIdPut`, and `deleteItemApiV1ItemsIdDelete`).

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:97-99`, on the `Item.owner_id`
foreign key. It tells PostgreSQL to delete dependent `item` rows when their
`user` row is deleted. Removing it would remove that database-level safety net:
direct SQL/database-level deletion of a user with items would fail with a
foreign-key violation (or leave dependents only if the constraint were also
changed to permit that), rather than cascading.

This repository also has compensating application behavior: `User.items` has
`cascade_delete=True` at `models.py:59`, `delete_user_me` calls
`session.delete(current_user)` (`backend/app/api/routes/users.py:132-143`), and
the admin `delete_user` route explicitly deletes matching `Item` rows first
(`users.py:214-231`).

The named existing deletion test is `test_delete_user_me` in
`backend/tests/api/routes/test_users.py:420-448`. However, precisely speaking,
the current function creates and deletes a user but creates no item and never
asserts dependent-item deletion. Therefore it would **not actually catch** the
loss of the database `ondelete` behavior; there is no existing test function in
this checkout that does. `test_delete_user_super_user` also deletes no item,
and the item tests do not delete users.

## 4. Why authenticate verifies `DUMMY_HASH`

`backend/app/crud.py:45-51` first looks up the email. If no user exists, it
still calls `verify_password(password, DUMMY_HASH)` and returns `None`.
`DUMMY_HASH` (`crud.py:40-42`) is a fixed Argon2 hash. Argon2 verification is
intentionally expensive, so doing the same password-hash work for an unknown
email makes the nonexistent-user path take roughly the same time as the
wrong-password path at `crud.py:52-54`. That reduces timing-based user/email
enumeration. The dummy result is discarded; it can never authenticate a user.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the application-level guard in
`backend/app/api/routes/items.py:48-58`, function `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

It runs after `session.get(Item, id)` (which yields a 404 at lines 53-55 if the
row is absent) and before returning the `Item`. The regression/behavior test is
`test_read_item_not_enough_permissions` in
`backend/tests/api/routes/test_items.py:55-65`, which expects 403. This is not
PostgreSQL row-level security; it is an explicit route check, with the
superuser exception.
