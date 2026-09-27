# Answers

## 1. `GET /api/v1/items/`

1. `backend/app/main.py`: the module creates `app = FastAPI(...)` and mounts
   `api_router` with `app.include_router(api_router, prefix=settings.API_V1_STR)`.
   `backend/app/core/config.py` supplies `API_V1_STR = "/api/v1"`.
2. `backend/app/api/main.py`: `api_router` includes `items.router`.
   `backend/app/api/routes/items.py` defines that router with prefix
   `"/items"`, tag `"items"`, and `@router.get("/", response_model=ItemsPublic)`.
   These prefixes produce `/api/v1/items/`.
3. FastAPI resolves `read_items`'s `SessionDep` and `CurrentUser` parameters from
   `backend/app/api/deps.py`. `SessionDep` is `Annotated[Session,
   Depends(get_db)]`; `get_db` opens `Session(engine)` using the engine imported
   from `backend/app/core/db.py`, yields it, and closes it on exit.
4. `CurrentUser` is `Annotated[User, Depends(get_current_user)]`. Before
   `read_items` runs, `get_current_user` in `backend/app/api/deps.py` uses the
   `TokenDep` bearer token supplied by `reusable_oauth2`, decodes it with
   `security.ALGORITHM` and `settings.SECRET_KEY`, validates `TokenPayload`,
   loads the user with `session.get(User, token_data.sub)`, and rejects a
   missing user (404) or inactive user (400). It returns the active `User`.
5. `backend/app/api/routes/items.py:14`, `read_items`, chooses its SQL based on
   `current_user.is_superuser`:
   - Superuser: counts all `Item` rows with `select(func.count()).select_from(Item)`;
     selects all items ordered by `Item.created_at` descending, then applies
     `skip` and `limit` (defaults 0 and 100).
   - Non-superuser: both the count query and item query add
     `where(Item.owner_id == current_user.id)`. The item query uses the same
     descending `created_at` ordering and pagination, so neither the returned
     `data` nor `count` includes another user’s items.
6. `read_items` converts each selected `Item` to `ItemPublic` with
   `ItemPublic.model_validate(item)` and returns `ItemsPublic(data=items_public,
   count=count)`. FastAPI serializes that response according to the
   `ItemsPublic` response model.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. Because
the items router has tag `items`, the operation ID for `read_items` is
`items-read_items`; this is why the generated client exposes
`ItemsService.readItems` in `frontend/src/client/sdk.gen.ts` (the generated
types use names such as `itemsReadItemsData`).

If `generate_unique_id_function=custom_generate_unique_id` were removed,
FastAPI's default generator would use the route name plus the path plus the
HTTP method. For this route its operation ID would be
`read_items_api_v1_items__get` (the slashes/braces become underscores), and the
generated TypeScript SDK method would consequently be named
`readItemsApiV1ItemsGet`. The other item methods would similarly be named
`createItemApiV1ItemsPost`, `readItemApiV1ItemsIdGet`,
`updateItemApiV1ItemsIdPut`, and `deleteItemApiV1ItemsIdDelete`, rather than
the current short names.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` currently makes `Item.owner_id` a non-nullable
foreign key with database-level `ON DELETE CASCADE`. Removing `ondelete` would
leave a normal restrictive foreign key: a direct database deletion of a
`user` row that still has `item` rows would fail with a foreign-key violation
instead of deleting those items.

There is an important codebase-specific qualification: no existing test
function actually catches that particular model-level regression. The two
application deletion paths already compensate for it:

- `delete_user_me` in `backend/app/api/routes/users.py:132-143` calls
  `session.delete(current_user)`, and the `User.items` relationship in
  `models.py:59` has SQLAlchemy/SQLModel `cascade_delete=True`.
- `delete_user` in `users.py:214-231` explicitly executes
  `delete(Item).where(col(Item.owner_id) == user_id)` before deleting the user.

`test_delete_user_me` (`backend/tests/api/routes/test_users.py:420`) and
`test_delete_user_super_user` (`:463`) exercise those routes, but neither
creates an Item, so neither would detect removal of the database `ON DELETE`
cascade. A regression test would need to create an item for a user, delete the
user through the relevant direct-parent-delete path, and assert the item is
gone (or that the delete does not fail).

## 4. Why `DUMMY_HASH` is verified

`backend/app/crud.py:45-51`, `authenticate`, first calls
`get_user_by_email`. If no user exists, it still calls
`verify_password(password, DUMMY_HASH)` and returns `None`. `verify_password`
in `backend/app/core/security.py:29-32` performs the expensive Argon2/bcrypt
verification. Doing that work on the nonexistent-user branch makes the
response time similar to the wrong-password branch for an existing user,
preventing an attacker from inferring whether an email address is registered
from timing differences. `DUMMY_HASH` is a fixed Argon2 hash of a random
password; its result is intentionally ignored.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the inline ownership guard in
`backend/app/api/routes/items.py:49-58`, inside `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

`read_item` first loads the row with `session.get(Item, id)` and returns 404 if
it does not exist; the guard then allows a superuser or the matching owner and
returns 403 for every other authenticated user. The corresponding existing
test is `test_read_item_not_enough_permissions` in
`backend/tests/api/routes/test_items.py:55-65`.
