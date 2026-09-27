# Answers

## 1. `GET /api/v1/items/`

The frontend path is:

1. `frontend/src/routes/_layout/items.tsx`: `ItemsTableContent()` uses TanStack Query with the object returned by `getItemsQueryOptions()`. Its `queryFn` calls `ItemsService.readItems({ query: { skip: 0, limit: 100 } })`.
2. `frontend/src/client/index.ts` re-exports `ItemsService` from `frontend/src/client/sdk.gen.ts`.
3. `frontend/src/client/sdk.gen.ts`: `ItemsService.readItems()` calls the generated client's `get()` with URL `/api/v1/items/`, query parameters, JSON response handling, and the bearer security scheme. The generated client obtains the configured auth token and sends it as `Authorization: Bearer ...` (the bearer formatting is in `frontend/src/client/core/auth.gen.ts`).
4. `backend/app/main.py`: `app` was created with `generate_unique_id_function=custom_generate_unique_id`, and `app.include_router(api_router, prefix=settings.API_V1_STR)` mounts the API under `/api/v1` (the configured value).
5. `backend/app/api/main.py`: `api_router` includes `items.router`.
6. `backend/app/api/routes/items.py`: `router` has prefix `/items` and `read_items()` is registered for `GET /`. FastAPI resolves its parameters through the dependencies declared by `SessionDep` and `CurrentUser`.
7. `backend/app/api/deps.py`: `get_db()` opens `Session(engine)` and yields it as `SessionDep`. `get_current_user()` decodes the bearer JWT with `jwt.decode()` using `settings.SECRET_KEY` and `security.ALGORITHM`, validates `TokenPayload`, loads the subject with `session.get(User, token_data.sub)`, and rejects a missing user (404) or inactive user (400). It returns the `User` as `CurrentUser`.
8. Back in `read_items()`, `backend/app/api/routes/items.py:21-42` branches on `current_user.is_superuser`:
   - Superuser: counts all `Item` rows with `select(func.count()).select_from(Item)`, then selects all items ordered by `created_at` descending, applying `skip` and `limit`.
   - Non-superuser: counts only rows where `Item.owner_id == current_user.id`, then selects only those same owner rows, with the same descending `created_at`, offset, and limit.
9. `read_items()` converts each result with `ItemPublic.model_validate(item)` and returns `ItemsPublic(data=items_public, count=count)`. FastAPI applies the declared `ItemsPublic` response model and serializes the response.

Thus a superuser receives the paginated global item list and global count; a normal active user receives only their own paginated items and their own-item count. Authentication is required for both.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines:

```python
return f"{route.tags[0]}-{route.name}"
```

FastAPI uses this as each route's OpenAPI `operationId`. For the items routes, the IDs are `items-read_items` and `items-read_item`. The generator configuration in `frontend/openapi-ts.config.ts:11-18` groups operations by tag, makes static service methods, names the class `{{name}}Service`, and removes the prefix through `name.replace(/^[^-]*-/, "")`. That produces `ItemsService.readItems()` and `ItemsService.readItem()` in `frontend/src/client/sdk.gen.ts`.

If the custom function were removed, FastAPI's installed default generator would use `route.name + route.path_format`, replace non-word characters with `_`, and append the HTTP method. These two operation IDs would therefore be `read_items_api_v1_items__get` and `read_item_api_v1_items__id__get`; with the current `@hey-api/openapi-ts` naming strategy, the generated methods would be `ItemsService.readItemsApiV1ItemsGet()` and `ItemsService.readItemApiV1ItemsIdGet()` (and the corresponding generated type names would retain those longer operation-name components).

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-100` currently makes `Item.owner_id` a non-null foreign key to `user.id` with database-level `ON DELETE CASCADE`; the migration that installed that constraint is `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:20-27`.

Removing the model field option would stop newly generated schema/migrations from declaring that database-level cascade. A database-level deletion of a `User` with dependent `Item` rows would then violate the foreign-key constraint instead of deleting those rows. The admin API path is additionally protected today because `backend/app/api/routes/users.py:214-231`, `delete_user()`, explicitly executes `delete(Item).where(col(Item.owner_id) == user_id)` before deleting the user. The self-delete path `delete_user_me()` at lines 132-143 does not issue that explicit item delete, so it relies on the relationship/database cascade behavior.

There is no existing test that actually creates an item owned by the deleted user and asserts that the item disappears. The closest named test is `backend/tests/api/routes/test_users.py::test_delete_user_me`, but it only asserts that the user row is gone (lines 443-448); `test_delete_user_super_user` likewise deletes a user without creating an item. Therefore no current test would reliably catch this specific item-cascade regression. A regression test would need to create an item for the user, delete that user, and assert the item is absent.

## 4. Why `DUMMY_HASH` is verified

`backend/app/crud.py:45-60`, `authenticate()`, first calls `get_user_by_email()`. When no user exists, it calls `verify_password(password, DUMMY_HASH)` and returns `None`. `DUMMY_HASH` is a fixed Argon2 hash specifically documented in lines 40-42 as timing-attack prevention. Argon2 verification is deliberately performed even for an unknown email, making the nonexistent-user path spend roughly the same password-hashing work as the existing-user path. Without it, an attacker could distinguish valid from invalid email addresses by response timing (email enumeration).

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the authorization guard in `backend/app/api/routes/items.py`, function `read_item()`, lines 53-58:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

In other words, after `CurrentUser` authenticates the request, the `not current_user.is_superuser and item.owner_id != current_user.id` pattern denies a non-owner with HTTP 403; superusers bypass that ownership check. The existing regression test is `backend/tests/api/routes/test_items.py::test_read_item_not_enough_permissions` (lines 55-65).
