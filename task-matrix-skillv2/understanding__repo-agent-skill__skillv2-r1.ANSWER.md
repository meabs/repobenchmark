# Answers

## 1. `GET /api/v1/items/`

1. `backend/app/main.py:21-25` constructs `app` with `generate_unique_id_function=custom_generate_unique_id`; line 35 includes `api_router` under `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py:6-10` builds `api_router` and includes `items.router`.
3. `backend/app/api/routes/items.py:10` declares `router` with prefix `/items`; `read_items` at lines 13-45 declares `@router.get("/", response_model=ItemsPublic)`, producing `/api/v1/items/`.
4. Before `read_items` runs, FastAPI resolves `SessionDep` and `CurrentUser` from `backend/app/api/deps.py`. `SessionDep` calls `get_db` (lines 21-23), which yields a `sqlmodel.Session(engine)` using the engine from `backend/app/core/db.py:7`. `CurrentUser` calls `get_current_user` (lines 30-46): it decodes the bearer token with `jwt.decode` using `settings.SECRET_KEY` and `security.ALGORITHM`, validates `TokenPayload`, loads the `User` by `token_data.sub`, and rejects a missing or inactive user.
5. `read_items` receives `skip` and `limit` (defaults 0 and 100). For a superuser (`current_user.is_superuser` true), lines 22-23 count all `Item` rows, and lines 24-27 select all items ordered by `Item.created_at` descending, then apply offset and limit. For a non-superuser, lines 29-34 count only rows with `Item.owner_id == current_user.id`, and lines 35-42 select only those same owned rows with the same ordering and pagination.
6. Lines 44-45 convert each selected ORM `Item` through `ItemPublic.model_validate` and return `ItemsPublic(data=items_public, count=count)`. `ItemPublic` is defined in `backend/app/models.py:103-107`; `ItemsPublic` is at lines 110-112. FastAPI serializes that response model.

Thus, superusers receive the globally paginated item list and total count; ordinary users receive only their own paginated list and owned-item count.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. For the items router (`tags=["items"]`), the GET collection route named `read_items` therefore gets OpenAPI operation ID `items-read_items`; the checked schema at `docs/api/openapi.json:731` has exactly that ID. The generated client maps it to `ItemsService.readItems` in `frontend/src/client/sdk.gen.ts:287-299`.

If the custom function were removed, FastAPI's default generator would use the route name, normalized path, and HTTP method. For these two GET routes the operation IDs would be:

- `read_items_api_v1_items__get` → generated client method `ItemsService.readItemsApiV1ItemsGet`.
- `read_item_api_v1_items__id__get` → generated client method `ItemsService.readItemApiV1ItemsIdGet`.

The double underscores in the operation IDs represent the trailing slash and `{id}` path-segment normalization; the TypeScript generator converts the identifiers to PascalCase method names.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` declares the database foreign key from `item.owner_id` to `user.id` with `ondelete="CASCADE"`. Removing it would remove database-level cascading: a direct SQL deletion of a user who still has items would fail with the foreign-key restriction instead of deleting those items. A migration would also be needed; the existing cascade was installed by `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:25-26`.

There is an important codebase-specific qualification: the existing application routes already cover this in two other ways. `User.items` has `cascade_delete=True` in `models.py:59`, so the ORM relationship handles `DELETE /users/me` in `backend/app/api/routes/users.py:132-143`; the admin `delete_user` route explicitly deletes `Item` rows first at lines 228-230. Also, no current test creates an item and then deletes its owner. Therefore there is no exact existing test function that would catch loss of the database-level cascade. `backend/tests/api/routes/test_users.py:test_delete_user_me` only asserts that the user row disappears (lines 420-449), and `test_delete_user_super_user` exercises the explicit bulk-item deletion path (lines 463-480); neither tests orphan-item cleanup. A regression test would need to create an owned item, delete the owner, and assert the item is gone.

## 4. `DUMMY_HASH`

In `backend/app/crud.py:45-60`, `authenticate` looks up the user by email. If no user exists, it still calls `verify_password(password, DUMMY_HASH)` at lines 47-50, then returns `None`. `verify_password` in `backend/app/core/security.py:29-32` performs the Argon2/bcrypt password verification work. This keeps the nonexistent-email path close to the existing-user path in timing, preventing an attacker from inferring whether an email is registered from response-time differences. `DUMMY_HASH` is a fixed Argon2 hash of a random password and is never used as a real user's credential.

## 5. Item ownership enforcement

The exact mechanism is the application-level guard in `backend/app/api/routes/items.py:48-58`, inside `read_item`, after `session.get(Item, id)`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

The corresponding existing regression test is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions` (lines 55-65). It creates an item owned by the test user fixture, requests it with `normal_user_token_headers`, and asserts HTTP 403 with that exact detail. This is an application check, not PostgreSQL row-level security.
