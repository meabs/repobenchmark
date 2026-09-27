# Codebase answers

## 1. `GET /api/v1/items/`

The backend path, in order, is:

1. `backend/app/main.py`: `app` is created with `custom_generate_unique_id`, and `app.include_router(api_router, prefix=settings.API_V1_STR)` mounts the API under `/api/v1`.
2. `backend/app/api/main.py`: `api_router` includes `items.router`.
3. `backend/app/api/routes/items.py`: `router` has prefix `/items` and tag `items`; its `@router.get("/")` handler is `read_items` (lines 13–45), producing `/api/v1/items/`.
4. Before `read_items` runs, `SessionDep` and `CurrentUser` are resolved from `backend/app/api/deps.py`: `get_db` opens `Session(engine)` from `backend/app/core/db.py` and yields it; `get_current_user` decodes the bearer token with `jwt.decode` using `settings.SECRET_KEY` and `security.ALGORITHM`, constructs `TokenPayload`, loads `User` with `session.get(User, token_data.sub)`, and rejects invalid, missing, or inactive users. `CurrentUser` is `Annotated[User, Depends(get_current_user)]`.
5. `read_items` checks `current_user.is_superuser`. For a superuser it counts all `Item` rows (`select(func.count()).select_from(Item)`) and selects all items, ordered by `Item.created_at` descending, with `skip`/`limit`. For a non-superuser it adds `Item.owner_id == current_user.id` to both the count query and item query, so both `count` and `data` contain only that user’s items; ordering and pagination are otherwise identical.
6. The handler validates each ORM item with `ItemPublic.model_validate`, then returns `ItemsPublic(data=items_public, count=count)`. `ItemPublic` and `ItemsPublic` are defined in `backend/app/models.py` (lines 103–112), and FastAPI applies `response_model=ItemsPublic`.

When called by the generated frontend client, `frontend/src/client/sdk.gen.ts` exposes this request as `ItemsService.readItems`; its generated request uses `GET /api/v1/items/` with bearer authentication.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14–15` defines:

```python
return f"{route.tags[0]}-{route.name}"
```

It uses the first route tag and Python endpoint function name to form the OpenAPI `operationId`. Thus `items.router`’s `read_items` operation gets `items-read_items`. `frontend/openapi-ts.config.ts:11–18` uses the `byTags` SDK strategy and removes the prefix through `name.replace(/^[^-]*-/, "")`; the generated method is therefore `readItems`, as seen in `frontend/src/client/sdk.gen.ts:287–300`.

If the custom function were removed, FastAPI’s default IDs would include the endpoint name, normalized path, and HTTP method. For the item routes they would be approximately:

| Route | Default OpenAPI ID | Generated SDK method (shape) |
|---|---|---|
| `GET /api/v1/items/` | `read_items_api_v1_items__get` | `readItemsApiV1ItemsGet` |
| `POST /api/v1/items/` | `create_item_api_v1_items__post` | `createItemApiV1ItemsPost` |
| `DELETE /api/v1/items/{id}` | `delete_item_api_v1_items__id__delete` | `deleteItemApiV1ItemsIdDelete` |
| `GET /api/v1/items/{id}` | `read_item_api_v1_items__id__get` | `readItemApiV1ItemsIdGet` |
| `PUT /api/v1/items/{id}` | `update_item_api_v1_items__id__put` | `updateItemApiV1ItemsIdPut` |

The final casing is the generator’s normal conversion from the underscore-separated operation ID; the configured `methodName` hook only strips a hyphenated tag prefix, which these default IDs do not have.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97–100` declares `Item.owner_id` as a non-null foreign key to `user.id` with `ondelete="CASCADE"`. The migration that installs the database-level behavior is `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22–26`.

Without that cascade, deleting a user who still owns items through `users.delete_user_me` in `backend/app/api/routes/users.py:132–143` would leave dependent rows and PostgreSQL would reject the user delete because `owner_id` is non-null and references the user. The ORM-side `User.items = Relationship(..., cascade_delete=True)` is also intended to cascade the relationship. The superuser delete endpoint is less dependent on the FK because `users.delete_user` explicitly bulk-deletes `Item` rows at lines 228–229 before deleting the user.

There is no current test function that actually catches this regression: `test_delete_user_me` in `backend/tests/api/routes/test_users.py:420–449` deletes a newly created user but never creates an Item owned by that user; `test_delete_user_super_user` likewise creates no item, and the latter endpoint explicitly deletes items anyway. `test_delete_user_me` is the existing test that would be the appropriate catcher if it first created an owned item, but as written it does not exercise `ondelete`.

## 4. Why verify `DUMMY_HASH`

`backend/app/crud.py:45–60` calls `get_user_by_email` first. If no user exists, it still calls `verify_password(password, DUMMY_HASH)` at lines 48–50 and returns `None`. `verify_password` in `backend/app/core/security.py:29–32` performs the expensive Argon2/bcrypt verification operation.

This makes the nonexistent-email path take approximately the same password-hashing time as the existing-email path. Without it, an attacker could distinguish registered from unregistered email addresses by measuring login response timing (a user-enumeration timing attack). The dummy hash is a fixed Argon2 hash of a random password, so it cannot authenticate the supplied password and its result is intentionally ignored.

## 5. Preventing cross-owner `GET /items/{id}` reads

The exact mechanism is the authorization guard in `backend/app/api/routes/items.py:48–58`, inside `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

`read_item` first loads the row by ID with `session.get(Item, id)` and returns 404 if absent; the guard then permits superusers or the matching owner and rejects every other authenticated user with 403. The corresponding regression test is `test_read_item_not_enough_permissions` in `backend/tests/api/routes/test_items.py:55–65`.
