# Answers

## 1. `GET /api/v1/items/`

If the request originates in the shipped UI, `frontend/src/routes/_layout/items.tsx`, `getItemsQueryOptions`, calls `ItemsService.readItems({ query: { skip: 0, limit: 100 } })`. The generated method is `frontend/src/client/sdk.gen.ts`, `ItemsService.readItems`; it issues the authenticated `GET` for `/api/v1/items/`.

On the backend, the request flows as follows:

1. `backend/app/main.py` constructs `app` and includes `api_router` at `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py` adds `items.router` to `api_router`. That router is declared in `backend/app/api/routes/items.py` with prefix `/items` and tag `items`; its `@router.get("/")` registration selects `read_items`.
3. Before `read_items` runs, `SessionDep` calls `backend/app/api/deps.py:get_db`, which opens a SQLModel `Session(engine)` using `backend/app/core/db.py:engine` and yields it. `CurrentUser` calls `backend/app/api/deps.py:get_current_user`: it decodes the bearer JWT with `jwt.decode` and the configured secret/HS256 algorithm, validates `TokenPayload`, loads the `User` with `session.get(User, token_data.sub)`, and rejects an absent user (404) or inactive user (400).
4. `backend/app/api/routes/items.py:read_items` branches on `current_user.is_superuser`.
   - For a superuser, it counts every `Item` with `select(func.count()).select_from(Item)`, then selects every item ordered by `Item.created_at` descending, applying `skip` and `limit`.
   - For a non-superuser, both the count query and item query add `where(Item.owner_id == current_user.id)`. The item query uses the same descending `created_at` ordering and pagination. Thus the count and `data` contain only that user’s items.
5. The function runs the statements with `session.exec(...).one()`/`.all()`, converts each result with `ItemPublic.model_validate(item)`, and returns `ItemsPublic(data=items_public, count=count)`. FastAPI validates/serializes that response as the `ItemsPublic` response model from `backend/app/models.py`.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines `custom_generate_unique_id(route: APIRoute)` as `f"{route.tags[0]}-{route.name}"`, and passes it as FastAPI’s `generate_unique_id_function` when constructing `app`. For the items router this changes operation IDs to `items-read_items` and `items-read_item`; `@hey-api/openapi-ts` turns those into the current methods `ItemsService.readItems` and `ItemsService.readItem` in `frontend/src/client/sdk.gen.ts`.

If the custom function were removed, FastAPI’s default operation IDs would be based on the Python route name, path, and HTTP method. The relevant generated TypeScript method names would therefore be based on IDs such as:

- `read_items_items__get` → `readItemsItemsGet`
- `read_item_items__id__get` → `readItemItemsIdGet`

The exact capitalization/formatting is the generator’s usual camel-case conversion; the important difference is that the tag prefix (`items-`) disappears and the path/method suffix is included.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` currently declares `Item.owner_id` as a non-nullable foreign key to `user.id` with database-level `ondelete="CASCADE"`. Removing it means newly generated/created database schema would no longer delete an Item automatically when its User row is deleted; a direct database-side User deletion could instead leave an orphan attempt and fail the foreign-key constraint.

There are two safeguards elsewhere in this checkout: `User.items` still has `Relationship(..., cascade_delete=True)` at `backend/app/models.py:59`, and `backend/app/api/routes/users.py:228-230`, `delete_user`, explicitly deletes Items whose `owner_id` matches the target user before deleting the user. Consequently, removing only the field option does not regress those current application paths, and the existing tests do not actually assert Item deletion: `test_delete_user_me` and `test_delete_user_super_user` create/delete users but create no Item. The closest exact existing test is `backend/tests/api/routes/test_users.py:test_delete_user_me`; strictly, no existing test function would catch an orphaned Item because none sets up an Item and verifies it is gone.

The schema’s intended cascade is also recorded in `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:25-26`, which creates the `item.owner_id → user.id` foreign key with `ondelete='CASCADE'`.

## 4. `DUMMY_HASH`

`backend/app/crud.py:45-51`, `authenticate`, calls `verify_password(password, DUMMY_HASH)` when `get_user_by_email` returns no user, then discards the result and returns `None`. `DUMMY_HASH` is a fixed Argon2 hash. The verification deliberately performs the expensive password-hash work on the nonexistent-user path, making failed login timing comparable to the existing-user/wrong-password path and reducing email/user-enumeration timing attacks. It does not authenticate the missing user or change the result.

## 5. Non-owner item reads

The exact authorization mechanism is in `backend/app/api/routes/items.py:53-58`, inside `read_item`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

The `not current_user.is_superuser` guard exempts superusers; otherwise the owner-ID comparison rejects a non-owner with HTTP 403 before the Item is returned. The existing regression test for this pattern is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`.
