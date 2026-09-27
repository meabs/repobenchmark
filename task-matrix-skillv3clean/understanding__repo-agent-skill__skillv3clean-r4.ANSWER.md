# Codebase answers

## 1. `GET /api/v1/items/`

The browser-side path is `frontend/src/routes/_layout/items.tsx`: `Items` renders
`ItemsTable`, whose `ItemsTableContent` calls `useSuspenseQuery` with
`getItemsQueryOptions()` (lines 12–17). Its `queryFn` calls the generated
`ItemsService.readItems` in `frontend/src/client/sdk.gen.ts:293-300`, which issues
an authenticated `GET /api/v1/items/` with `skip=0` and `limit=100`. The service is
re-exported by `frontend/src/client/index.ts:3`.

On the backend, the order is:

1. `backend/app/main.py:21-25` constructs `app` with
   `generate_unique_id_function=custom_generate_unique_id`; line 35 includes
   `api_router` with `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py:6-10` constructs `api_router` and includes
   `items.router`.
3. `backend/app/api/routes/items.py:10` defines the router with prefix `/items`
   and tag `items`; `read_items` at lines 13–45 is therefore the handler for
   `GET /api/v1/items/`.
4. FastAPI resolves `SessionDep` through `backend/app/api/deps.py:21-23`,
   `get_db`, which opens `Session(engine)` and yields it. It resolves
   `CurrentUser` through `get_current_user` at `deps.py:30-46`: the bearer token
   is decoded with `jwt.decode` using `settings.SECRET_KEY` and
   `security.ALGORITHM`, validated as `TokenPayload`, then used by
   `session.get(User, token_data.sub)`. A missing user gives 404 and an inactive
   user gives 400.
5. `read_items` branches on `current_user.is_superuser`:
   - Superuser: lines 21–27 count all `Item` rows, then select all items ordered
     by `Item.created_at` descending, applying `skip` and `limit`.
   - Non-superuser: lines 29–42 count only rows where
     `Item.owner_id == current_user.id`, then select only those same-owner rows,
     with the same descending ordering and pagination.
6. Lines 44–45 validate each ORM `Item` as `ItemPublic` and return
   `ItemsPublic(data=items_public, count=count)`. `ItemPublic` is defined in
   `backend/app/models.py:103-107`; `ItemsPublic` is at lines 110–112. The
   response is serialized against `response_model=ItemsPublic`.

Thus a superuser sees every item and the global count; an ordinary active user
sees only their own items and their own-item count. The same ownership filter is
in the count query and item query, so pagination does not change that distinction.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns
`f"{route.tags[0]}-{route.name}"`. For the items router this turns FastAPI route
names into IDs such as `items-read_items`, `items-read_item`,
`items-create_item`, `items-update_item`, and `items-delete_item`. Those IDs are
visible in `docs/api/openapi.json` (for example `items-read_items` at line 731).

The generator configuration in `frontend/openapi-ts.config.ts:11-18` groups by
tags and applies `methodName: name => name.replace(/^[^-]*-/, "")`; consequently
`items-read_items` becomes the generated `ItemsService.readItems` method (and
similarly `readItem`, `createItem`, `updateItem`, and `deleteItem`).

If the custom function were removed, FastAPI's default
`fastapi.routing.generate_unique_id` would use
`route.name + route.path_format`, replace non-word characters with `_`, and append
the first HTTP method in lowercase. With the registered `/api/v1` prefix, the
items operation IDs would be:

- `read_items_api_v1_items__get`
- `create_item_api_v1_items__post`
- `read_item_api_v1_items__id__get`
- `update_item_api_v1_items__id__put`
- `delete_item_api_v1_items__id__delete`

Because those IDs contain no hyphen, the configured `methodName` regex would not
strip anything. The generated static client method names would therefore be the
camel-cased forms `readItemsApiV1ItemsGet`, `createItemApiV1ItemsPost`,
`readItemApiV1ItemsIdGet`, `updateItemApiV1ItemsIdPut`, and
`deleteItemApiV1ItemsIdDelete` (inside `ItemsService`).

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:97-100`:

```python
owner_id: uuid.UUID = Field(
    foreign_key="user.id", nullable=False, ondelete="CASCADE"
)
```

That option represents the database foreign-key action. The corresponding
Alembic change is `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`, which creates the FK with `ondelete='CASCADE'`.
Removing it from the model means a newly generated/applied schema would no longer
delete an owner's `Item` rows at the database level when the `User` row is deleted;
direct database deletion would instead be rejected by the non-cascading FK (and
would not leave orphan rows).

There are two important current-code qualifications. `User.items` at
`models.py:59` has SQLAlchemy/SQLModel `cascade_delete=True`, so ORM deletion via
`delete_user_me` in `backend/app/api/routes/users.py:132-143` still has an ORM
cascade. Also, the privileged `delete_user` function at `users.py:214-232`
explicitly executes `DELETE FROM item WHERE owner_id == user_id` before deleting
the user. Therefore removing only the model option does not break either current
application deletion path unless the database schema is also migrated and the ORM
cascade is not used.

The exact existing deletion test function is
`backend/tests/api/routes/test_users.py::test_delete_user_me` (lines 420–448),
but it only asserts that the user disappears; it creates no Item and does not
assert cascade behavior. `test_delete_user_super_user` also does not test the FK
cascade because the endpoint explicitly deletes Items first. Consequently, no
existing test actually catches an orphaned Item/non-cascading FK regression; a
test that created an Item for the deleted user and then asserted that Item was
gone would be required.

## 4. Why authenticate verifies `DUMMY_HASH`

`backend/app/crud.py:45-60` first calls `get_user_by_email` (lines 34–37). If no
user is found, lines 48–50 still call `verify_password(password, DUMMY_HASH)` and
then return `None`. `verify_password` in `backend/app/core/security.py:29-32`
performs the expensive Argon2/bcrypt `verify_and_update` operation.

Without that call, a nonexistent email would return after a cheap database lookup,
while an existing email would spend time verifying its password. That timing
difference could reveal whether an email is registered. The fixed Argon2 hash is
therefore a timing-attack defense: both branches perform comparable password-hash
work, while the nonexistent-user branch still authenticates nobody.

## 5. Single-item ownership protection

The exact mechanism is the inline guard in
`backend/app/api/routes/items.py::read_item`, lines 53–58:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

`current_user` is injected by the `CurrentUser` dependency in
`backend/app/api/deps.py:49`, so the guard compares the loaded Item's
`owner_id` with the authenticated user's ID and makes superusers the sole
exception. The existing regression/behavior test is
`backend/tests/api/routes/test_items.py::test_read_item_not_enough_permissions`
(lines 55–65), which expects HTTP 403 and the exact detail string.
