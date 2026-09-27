# Answers

## 1. `GET /api/v1/items/` request path

From the frontend, `frontend/src/routes/_layout/items.tsx` calls `getItemsQueryOptions()` (line 12), whose `queryFn` calls `ItemsService.readItems({ query: { skip: 0, limit: 100 } })` (lines 14–15). `frontend/src/client/sdk.gen.ts` implements `ItemsService.readItems` (lines 287–300); it calls the generated client's `get` method with URL `/api/v1/items/` and bearer security. `frontend/src/main.tsx` configures that client at lines 17–20, taking the base URL from `VITE_API_URL` and the token from `localStorage["access_token"]`. In `frontend/src/client/client/client.gen.ts`, `makeMethodFn` creates `get` (lines 114–115 and 138), `beforeRequest` calls `setAuthParams` for the bearer token (lines 38–66), and `request` sends the Axios request (lines 69–112).

On the backend, the order is:

1. `backend/app/main.py`: `app` is constructed with `custom_generate_unique_id` (lines 21–25), and `api_router` is mounted at `settings.API_V1_STR` by `app.include_router` (line 35).
2. `backend/app/api/main.py`: `api_router` includes `items.router` (line 10).
3. `backend/app/api/routes/items.py`: `router` declares prefix `/items` and tag `items` (line 10); its `read_items` handler is registered for `GET /` (lines 13–16), producing the full `/api/v1/items/` route.
4. FastAPI resolves `SessionDep` and `CurrentUser` in `read_items`. `SessionDep` is `Annotated[Session, Depends(get_db)]` in `backend/app/api/deps.py` (line 26); `get_db` opens `Session(engine)` and yields it (lines 21–23), with `engine` created in `backend/app/core/db.py:7`. `CurrentUser` depends on `get_current_user` (`backend/app/api/deps.py:49`). That function decodes the bearer JWT with `jwt.decode` (lines 30–35), validates `TokenPayload`, loads `User` with `session.get(User, token_data.sub)` (line 41), and rejects invalid, missing, or inactive users (lines 36–46).
5. `read_items` (`backend/app/api/routes/items.py:14`) branches on `current_user.is_superuser`:
   - Superuser: counts all `Item` rows (`select(func.count()).select_from(Item)`, lines 21–23), then selects all items ordered by `created_at` descending, applying `skip` and `limit` (lines 24–27).
   - Non-superuser: counts only rows where `Item.owner_id == current_user.id` (lines 28–34), then selects only those same owner rows, with the same descending order and pagination (lines 35–42).
6. The handler converts each result with `ItemPublic.model_validate` and returns `ItemsPublic(data=items_public, count=count)` (`items.py:44–45`). FastAPI serializes that response as the `ItemsPublic` response model.

Thus a superuser receives the paginated global item set and global count; a non-superuser receives only their own paginated items and their own-item count.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14–15` returns `f"{route.tags[0]}-{route.name}"`. For this route, the tag is `items` and the function name is `read_items`, so the OpenAPI operation ID is `items-read_items`. The Hey API configuration in `frontend/openapi-ts.config.ts:11–18` uses `byTags`, creates `{{name}}Service` containers, and strips the prefix through `name.replace(/^[^-]*-/, "")`. Consequently the generated method is `ItemsService.readItems` in `frontend/src/client/sdk.gen.ts:293`.

If the custom generator were removed, FastAPI's default operation ID would include the function, path, and method— for this endpoint, `read_items_api_v1_items__get`. The generated client would therefore use the corresponding camel-cased operation name, approximately `ItemsService.readItemsApiV1ItemsGet` (with the same `byTags` `ItemsService` grouping), rather than the concise `readItems`.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97–99` declares `Item.owner_id` as a non-null foreign key to `user.id` with `ondelete="CASCADE"`. Removing it means the database foreign key no longer deletes an owner's `Item` rows when the `User` row is deleted; a direct database/user delete with existing child items would instead be rejected by the foreign-key constraint (unless the children are deleted first).

There is no existing test function that actually catches this regression. `backend/tests/api/routes/test_users.py::test_delete_user_me` (line 420) is the closest relevant test, but it creates/deletes a user without creating an Item and only asserts that the User is gone. `test_delete_user_super_user` also does not create or inspect items, and `users.py:228–230` explicitly deletes items in the superuser-by-ID path. Moreover, `User.items` has `cascade_delete=True` at `models.py:59`, so the ORM can still cascade a `session.delete(current_user)` independently of the database FK option. A test that would catch the database-FK regression would need to create an Item owned by the deleted user and assert it is deleted (or exercise a direct database delete); no such test exists here.

## 4. Why verify `DUMMY_HASH`

`backend/app/crud.py:40–42` defines `DUMMY_HASH` as a valid Argon2 hash. In `authenticate` (`crud.py:45–60`), when `get_user_by_email` finds no user, line 50 still calls `verify_password(password, DUMMY_HASH)` before returning `None`. `verify_password` delegates to `password_hash.verify_and_update` in `backend/app/core/security.py:29–32`, which performs the expensive password-hash work. Doing that on the nonexistent-user path keeps authentication timing similar to the existing-user path, reducing email/user enumeration via timing attacks; it does not authenticate the request.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the inline ownership guard in `backend/app/api/routes/items.py`, function `read_item`, lines 53–58:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

The `current_user` value comes from `CurrentUser`/`get_current_user` in `backend/app/api/deps.py:30–49`. The exact regression test for this behavior is `backend/tests/api/routes/test_items.py::test_read_item_not_enough_permissions` (line 55), which expects HTTP 403 and the same detail.
