# Answers

## 1. `GET /api/v1/items/`

From the frontend, `frontend/src/routes/_layout/items.tsx:getItemsQueryOptions` calls `ItemsService.readItems` with `skip=0` and `limit=100`. `frontend/src/client/sdk.gen.ts:ItemsService.readItems` issues an authenticated `GET` to `/api/v1/items/` (the generated method is backed by the operation ID `items-read_items`).

On the backend, the request is handled in this order:

1. `backend/app/main.py` creates `app`, installs `custom_generate_unique_id`, and calls `app.include_router(api_router, prefix=settings.API_V1_STR)`. `settings.API_V1_STR` is `/api/v1`, from `backend/app/core/config.py:Settings`.
2. `backend/app/api/main.py` imports `items`, then `api_router.include_router(items.router)`. `backend/app/api/routes/items.py` defines `router = APIRouter(prefix="/items", tags=["items"])`, so its `@router.get("/")` route becomes `/api/v1/items/`.
3. Before `read_items`, FastAPI resolves `SessionDep` and `CurrentUser` from `backend/app/api/deps.py`. `SessionDep` calls `get_db`, which opens `Session(engine)` using `backend/app/core/db.py:engine`. `CurrentUser` calls `get_current_user`; its `reusable_oauth2` dependency extracts the bearer token, `jwt.decode` verifies it with `settings.SECRET_KEY` and `security.ALGORITHM` (`HS256`) from `backend/app/core/security.py`, `TokenPayload` reads `sub`, and `session.get(User, token_data.sub)` loads the user. Missing or inactive users produce the corresponding HTTP errors.
4. `backend/app/api/routes/items.py:read_items` receives the session, loaded user, `skip`, and `limit`.
5. For a superuser (`current_user.is_superuser` is true), `read_items` counts every `Item` with `select(func.count()).select_from(Item)`, then selects every `Item`, ordered by `Item.created_at` descending and constrained by `offset(skip).limit(limit)`.
6. For a non-superuser, it adds `where(Item.owner_id == current_user.id)` to both the count query and the item query. Thus both `count` and `data` contain only that user’s items; another user’s items are not merely omitted from the response—they are excluded from the database queries.
7. The selected ORM objects are converted with `ItemPublic.model_validate(item)`, and `read_items` returns `ItemsPublic(data=items_public, count=count)`. FastAPI serializes that response according to `response_model=ItemsPublic`.

## 2. `custom_generate_unique_id`

`backend/app/main.py:custom_generate_unique_id(route)` returns `f"{route.tags[0]}-{route.name}"`. For the items router, this makes the operation IDs use the tag and function name, for example `items-read_items`, `items-create_item`, `items-read_item`, `items-update_item`, and `items-delete_item`.

`frontend/openapi-ts.config.ts` configures the generated SDK with `methodName: (name) => name.replace(/^[^-]*-/, "")`, so `items-read_items` becomes the client method `readItems` in `frontend/src/client/sdk.gen.ts:ItemsService`.

If `generate_unique_id_function=custom_generate_unique_id` were removed, FastAPI’s default generator would use `route.name + route.path_format`, replace non-word characters with underscores, and append the HTTP method. For this mounted route the operation ID would be `read_items_api_v1_items__get`; the generated client method would correspondingly be `readItemsApiV1ItemsGet`. The item methods would similarly be named `createItemApiV1ItemsPost`, `readItemApiV1ItemsIdGet`, `updateItemApiV1ItemsIdPut`, and `deleteItemApiV1ItemsIdDelete` (with the exact capitalization produced by the TypeScript generator).

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:Item.owner_id`: `Field(foreign_key="user.id", nullable=False, ondelete="CASCADE")`. The matching database migration is `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:upgrade`, which creates the `item_owner_id_fkey` foreign key with `ondelete='CASCADE'`.

Removing it would remove database-level cascading when a parent `user` row is deleted: a direct database delete of a user with dependent items would fail with a foreign-key violation (or, if referential enforcement were otherwise weakened, leave dependent items rather than deleting them). It would not change the item-list filtering or the single-item authorization.

There is no existing test that catches this specific model/database regression. In particular, `backend/tests/api/routes/test_users.py:test_delete_user_me` deletes a user but creates no item for that user, and `test_delete_user_super_user` also creates no item. Moreover, `backend/app/api/routes/users.py:delete_user` explicitly bulk-deletes that user’s `Item` rows before deleting the user, while the `User.items` relationship in `models.py` has `cascade_delete=True`. A test that would actually catch removal of the FK action would need to create a user plus an item, delete the user through a path that relies on database cascade, and assert the item is gone; no such test exists in the inspected suite.

## 4. `DUMMY_HASH` in `crud.authenticate`

`backend/app/crud.py:authenticate` first calls `get_user_by_email`. If no user is found, it still calls `verify_password(password, DUMMY_HASH)` and returns `None`. `DUMMY_HASH` is a fixed Argon2 hash of a random password, documented in the file as being for timing-attack prevention.

Password-hash verification is deliberately expensive. Without the dummy verification, nonexistent-email logins would return faster than wrong-password logins for existing accounts, allowing an attacker to enumerate registered email addresses by measuring response times. Verifying the dummy hash makes both branches perform comparable password work, while still returning the same authentication failure (`None`).

## 5. Reading another user’s item by ID

The mechanism is the ownership check in `backend/app/api/routes/items.py:read_item`, immediately after `session.get(Item, id)`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

Therefore a non-owner receives HTTP 403, while a superuser bypasses the owner comparison. The exact regression test is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`, which creates an item owned by a different random user and asserts status 403 plus the same detail string.
