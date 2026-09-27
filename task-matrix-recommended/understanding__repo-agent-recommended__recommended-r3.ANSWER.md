# Answers

## 1. `GET /api/v1/items/`

The frontend call path is:

1. `frontend/src/routes/_layout/items.tsx:12-17`, `getItemsQueryOptions`, creates the TanStack Query options. Its `queryFn` calls `ItemsService.readItems({ query: { skip: 0, limit: 100 } })`.
2. `frontend/src/client/sdk.gen.ts:287-300`, `ItemsService.readItems`, uses the generated client’s `get` method with URL `/api/v1/items/`, bearer security, and the query options. The shared client implementation is in `frontend/src/client/client/` (the generated request machinery); the configured client is exported by `frontend/src/client/client.gen.ts`.
3. `backend/app/main.py:21-25` constructs the FastAPI app, and `backend/app/main.py:35` includes `api_router` with prefix `settings.API_V1_STR`. `backend/app/core/config.py:22` sets that prefix to `/api/v1`.
4. `backend/app/api/main.py:6-10` builds `api_router` and includes `items.router`. `backend/app/api/routes/items.py:10` gives that router prefix `/items` and tag `items`; `items.py:13-16`, `read_items`, is therefore the handler for `/api/v1/items/`.
5. FastAPI resolves `SessionDep` and `CurrentUser` in the handler signature (`backend/app/api/routes/items.py:15`). `SessionDep` is `Annotated[Session, Depends(get_db)]` at `backend/app/api/deps.py:21-26`; `get_db` opens a SQLModel `Session(engine)` and yields it. `CurrentUser` is `Annotated[User, Depends(get_current_user)]` at `backend/app/api/deps.py:30-49`. `get_current_user` decodes the bearer JWT with `jwt.decode` (`deps.py:30-40`), loads the user with `session.get(User, token_data.sub)` (`deps.py:41`), rejects a missing user with 404 and an inactive user with 400, and returns the active `User`.
6. `backend/app/api/routes/items.py:21-42` branches on `current_user.is_superuser`. For a superuser, it counts all rows with `select(func.count()).select_from(Item)` (`items.py:22-23`), then selects all `Item` rows ordered by `created_at` descending, applying `skip` and `limit` (`items.py:24-27`). For a non-superuser, both the count query (`items.py:29-34`) and item query (`items.py:35-42`) add `where(Item.owner_id == current_user.id)`, so the count and returned page contain only that user’s Items; ordering, offset, and limit are otherwise identical.
7. The handler converts each ORM `Item` to `ItemPublic` at `items.py:44` and returns `ItemsPublic(data=items_public, count=count)` at `items.py:45`. `ItemPublic` exposes `id`, `owner_id`, `created_at`, `title`, and `description` (`backend/app/models.py:103-107`), and `ItemsPublic` contains `data` and `count` (`models.py:110-112`). FastAPI validates/serializes that response under the declared `response_model=ItemsPublic` (`items.py:13`).

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines `custom_generate_unique_id(route)` as `f"{route.tags[0]}-{route.name}"`. `backend/app/main.py:24` passes it as FastAPI’s `generate_unique_id_function`. Thus the items operation IDs are tag plus function name, for example `items-read_items`, and the generated client currently exposes `ItemsService.readItems` (`frontend/src/client/sdk.gen.ts:293`).

If that override were removed, FastAPI’s default generator would incorporate the route name, full path, and HTTP method. The operation IDs (and, with this repo’s `frontend/openapi-ts.config.ts` method naming rule, the generated `ItemsService` method names) would be:

| Operation | Default operation ID | Generated method |
|---|---|---|
| `GET /api/v1/items/` | `read_items_api_v1_items__get` | `readItemsApiV1ItemsGet` |
| `POST /api/v1/items/` | `create_item_api_v1_items__post` | `createItemApiV1ItemsPost` |
| `GET /api/v1/items/{id}` | `read_item_api_v1_items__id__get` | `readItemApiV1ItemsIdGet` |
| `PUT /api/v1/items/{id}` | `update_item_api_v1_items__id__put` | `updateItemApiV1ItemsIdPut` |
| `DELETE /api/v1/items/{id}` | `delete_item_api_v1_items__id__delete` | `deleteItemApiV1ItemsIdDelete` |

The extra words are significant: the SDK config (`frontend/openapi-ts.config.ts`) strips only a leading tag prefix ending in `-`; these default IDs have no such prefix.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` currently declares `Item.owner_id` as a non-nullable foreign key to `user.id` with database-level `ondelete="CASCADE"`. Removing it means deleting a `User` at the database level would no longer cause PostgreSQL to delete that user’s Item rows; with dependent rows still present, a direct database delete could instead fail the foreign-key constraint (and a deletion path that relied only on the FK would leave the intended cascade behavior broken).

There is no existing test function that catches this specific regression. `backend/tests/api/routes/test_users.py:test_delete_user_me` only creates and deletes a user and checks that the user is gone; it creates no Item and does not assert child deletion. `test_delete_user_super_user` also does not exercise the FK cascade: `backend/app/api/routes/users.py:228-230` explicitly executes `delete(Item).where(col(Item.owner_id) == user_id)` before deleting the user. The model also has the ORM-side `Relationship(..., cascade_delete=True)` at `models.py:59`, so the current user-object deletion path is not a pure test of the database FK’s `ondelete`. A regression test would need to create an Item for a user, delete the user through a path that does not explicitly delete Items, and assert the Item is gone (or that the intended database cascade remains configured).

## 4. Why `authenticate` verifies `DUMMY_HASH`

`backend/app/crud.py:45-60` first calls `get_user_by_email`. If no user is found (`crud.py:47`), it still calls `verify_password(password, DUMMY_HASH)` at `crud.py:50`, then returns `None`. `DUMMY_HASH` (`crud.py:40-42`) is a fixed Argon2 hash of a random password. `verify_password` delegates to `password_hash.verify_and_update` (`backend/app/core/security.py:29-32`), which performs the expensive password-hash work.

This keeps the nonexistent-email path’s timing similar to the wrong-password path (`crud.py:52-54`), reducing email/user enumeration through response-time measurements. It does not authenticate the user: the dummy result is ignored and the function returns `None`.

## 5. Non-owner access to `GET /items/{id}`

The exact mechanism is the ownership guard in `backend/app/api/routes/items.py:53-58`, inside `read_item`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

The `not current_user.is_superuser` exception makes the guard apply only to non-superusers; a non-owner non-superuser receives HTTP 403 before the `ItemPublic` response is returned. The corresponding existing regression test is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions` (`test_items.py:55-65`).
