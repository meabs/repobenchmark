# Answers

## 1. `GET /api/v1/items/`

The server-side path is:

1. `backend/app/main.py:21-25` creates `app` with
   `generate_unique_id_function=custom_generate_unique_id`; line 35 mounts
   `api_router` under `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py:6-10` builds `api_router` and includes
   `items.router`.
3. `backend/app/api/routes/items.py:10` defines that router with prefix
   `/items` and tag `items`; `read_items` at lines 13-16 handles `GET /` and
   declares `response_model=ItemsPublic`.
4. FastAPI resolves `SessionDep` through `backend/app/api/deps.py:21-23`, whose
   `get_db` opens `Session(engine)` in a context manager (`engine` comes from
   `backend/app/core/db.py`). It resolves `CurrentUser` through
   `get_current_user` at `deps.py:30-46`: `jwt.decode` validates the bearer
   token with `settings.SECRET_KEY` and `security.ALGORITHM`, `TokenPayload`
   reads `sub`, `session.get(User, token_data.sub)` loads the user, and missing
   or inactive users raise 404/400. `CurrentUser` is the annotated dependency
   at `deps.py:49`.
5. `read_items` branches at `backend/app/api/routes/items.py:21`. For a
   superuser, it counts every `Item` (`select(func.count()).select_from(Item)`)
   and selects every item, ordered by `Item.created_at` descending, then applies
   `skip` and `limit` (lines 22-27). For a non-superuser, both the count query
   (lines 29-34) and item query (lines 35-42) add
   `Item.owner_id == current_user.id`; it therefore cannot see another user's
   rows or have them included in `count`. Both branches use defaults
   `skip=0`, `limit=100`.
6. Lines 44-45 validate each SQLModel row as `ItemPublic` and return
   `ItemsPublic(data=items_public, count=count)`. `ItemPublic` and
   `ItemsPublic` are defined in `backend/app/models.py:103-112`; FastAPI serializes
   that response against the declared response model.

The generated frontend caller for this operation is
`frontend/src/client/sdk.gen.ts:293-300`, `ItemsService.readItems`; the Items
page calls it from `frontend/src/routes/_layout/items.tsx:15` with `skip: 0` and
`limit: 100`.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. FastAPI
uses it at line 24 for OpenAPI operation IDs. Thus the items list operation is
`items-read_items` (also present at `docs/api/openapi.json:731`), which the
generated client turns into `ItemsService.readItems`.

If the custom function were removed, FastAPI's default IDs would include the
function name, normalized path, and HTTP method. For the five item operations,
the generated method names would consequently be approximately:

- `ItemsService.readItemsApiV1ItemsGet`
- `ItemsService.createItemApiV1ItemsPost`
- `ItemsService.readItemApiV1ItemsIdGet`
- `ItemsService.updateItemApiV1ItemsIdPut`
- `ItemsService.deleteItemApiV1ItemsIdDelete`

The service grouping remains based on the `items` tag; the method names change
because the operation IDs change from the short `items-<route name>` form.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` currently declares a non-null foreign key from
`item.owner_id` to `user.id` with database-level `ON DELETE CASCADE`.
Removing it would make a freshly migrated/generated constraint use the default
restricting behavior: a direct database delete of a user that still has Item
rows would fail instead of deleting those rows. It would also make the model
disagree with the existing cascade migration,
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`,
which creates the `ondelete='CASCADE'` foreign key.

There is no existing test function that actually catches this specific
regression. `test_delete_user_me` in
`backend/tests/api/routes/test_users.py:420-448` deletes a user but creates no
Item first, and `test_delete_user_super_user` at lines 463-479 also creates no
Item. Moreover, the latter route explicitly deletes Items at
`backend/app/api/routes/users.py:214-231`, while the self-delete route uses the
SQLModel relationship's `cascade_delete=True` at `models.py:59`. A regression
test would need to create an Item for a user, delete the user through the
database-level path (or otherwise exercise the FK), and assert the Item is gone;
no such test exists in the repository.

## 4. Why authenticate verifies `DUMMY_HASH`

`backend/app/crud.py:45-51` first looks up the email with
`get_user_by_email`. When no row exists, it still calls
`verify_password(password, DUMMY_HASH)` and then returns `None`.
`DUMMY_HASH` at lines 40-42 is a fixed Argon2 hash. `verify_password` delegates
to `PasswordHash.verify_and_update` in `backend/app/core/security.py:29-32`.

Password-hash verification is deliberately expensive. Performing the same
verification work for unknown and known emails keeps login response timing
similar, reducing the ability to enumerate registered email addresses through a
timing side channel. The dummy result is ignored; it exists only to equalize
the work.

## 5. Reading another user's Item by ID

The exact mechanism is the application-level guard in
`backend/app/api/routes/items.py`, function `read_item`, lines 53-57:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

Thus a non-owner receives 403, while a superuser bypasses the owner comparison.
The corresponding regression test is `test_read_item_not_enough_permissions`
in `backend/tests/api/routes/test_items.py:55-65`.
