# Answers

## 1. `GET /api/v1/items/`

1. `backend/app/main.py`: the module creates `app = FastAPI(...)` and, at line 35,
   mounts `api_router` under `settings.API_V1_STR` (`/api/v1`).
2. `backend/app/api/main.py`: module import constructs `api_router` and
   `include_router(items.router)`; `backend/app/api/routes/items.py` defines that
   router with prefix `/items` and tag `items`.
3. FastAPI resolves `read_items` in `backend/app/api/routes/items.py:14`. Its
   `session: SessionDep` dependency invokes `backend/app/api/deps.py:get_db`,
   which opens `Session(engine)` in a context manager and yields it. Its
   `current_user: CurrentUser` dependency invokes `get_current_user` in the same
   file: it decodes the bearer JWT with `jwt.decode`, validates `TokenPayload`,
   loads `User` by the token subject with `session.get`, and rejects invalid,
   missing, or inactive users (403/404/400 respectively). `TokenDep` is supplied
   by `OAuth2PasswordBearer`, which extracts the bearer token.
4. `read_items` branches on `current_user.is_superuser`:
   - Superuser: counts all `Item` rows (`select(func.count()).select_from(Item)`),
     then selects all items ordered by `created_at` descending, applying `skip`
     and `limit`.
   - Non-superuser: counts only rows with `Item.owner_id == current_user.id`,
     then selects only those rows with the same descending order and pagination.
5. In either branch, each ORM `Item` is converted with
   `ItemPublic.model_validate` (the response model from `backend/app/models.py`),
   and `read_items` returns `ItemsPublic(data=items_public, count=count)`. FastAPI
   serializes that response as the declared `ItemsPublic` response model.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. Since the
items router is tagged `items` and the function for `GET /items/` is named
`read_items`, its operation ID is `items-read_items`. The FastAPI app installs this
function through `generate_unique_id_function=custom_generate_unique_id` at line
24. The generated client therefore has names such as
`ItemsService.readItems` (from `frontend/src/client/sdk.gen.ts:287-300`).

If the custom function were removed, FastAPI's default path/method-derived IDs
would be used. The generated names would consequently be verbose names such as
`ItemsService.readItemsItemsGet` (and corresponding path/method suffixes for the
other operations), rather than the short tag/function-derived names.

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:97-99`, where `Item.owner_id` is a
non-nullable foreign key to `user.id`. Removing `ondelete="CASCADE"` removes the
database-level cascade from that foreign-key constraint: a raw SQL deletion of a
user that still has item rows would fail the foreign-key constraint instead of
deleting those rows.

For the application paths currently present, this particular removal is largely
masked: `User.items` at `models.py:59` has SQLAlchemy `cascade_delete=True`,
`delete_user_me` at `backend/app/api/routes/users.py:132-143` deletes the loaded
user through the ORM, and `delete_user` at lines 214-231 explicitly deletes the
user's `Item` rows before deleting the user.

There is no existing test that actually creates an item for the user and verifies
database-level `ondelete` behavior. The closest test is
`backend/tests/api/routes/test_users.py:test_delete_user_me`; it only creates and
deletes a user and asserts that the user is gone, so it would not catch removal of
the database cascade. `test_delete_user_super_user` likewise creates no item.

## 4. `DUMMY_HASH`

`backend/app/crud.py:45-60` first looks up the email. When no user exists, it
still calls `verify_password(password, DUMMY_HASH)` and then returns `None`.
`verify_password` in `backend/app/core/security.py:29-32` performs the expensive
password-hash verification. Running the same expensive operation for nonexistent
and existing accounts keeps response timing similar, preventing an attacker from
using timing differences to enumerate registered email addresses. `DUMMY_HASH`
is a fixed Argon2 hash of a random password; its result is intentionally ignored.

## 5. Non-owner access to `GET /items/{id}`

The exact mechanism is the inline ownership guard in
`backend/app/api/routes/items.py:53-58`, inside `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

The preceding `session.get(Item, id)` returns 404 for a missing item; for an
existing item owned by another non-superuser, this guard returns 403. The exact
regression test is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`.
