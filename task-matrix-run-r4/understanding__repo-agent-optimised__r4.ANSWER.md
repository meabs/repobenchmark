# Answers

## 1. `GET /api/v1/items/`

1. `backend/app/main.py` creates the FastAPI `app` with `generate_unique_id_function=custom_generate_unique_id` and includes `api_router` at `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py` imports `items.router` and includes it in `api_router`.
3. `backend/app/api/routes/items.py:10` defines that router with prefix `/items` and tag `items`; line 13 registers `GET /` as `read_items`, so the full path is `/api/v1/items/`.
4. FastAPI resolves `SessionDep` and `CurrentUser` before calling the handler. `SessionDep` is `Depends(get_db)` in `backend/app/api/deps.py:21-23`; `get_db` opens `Session(engine)` and yields it. `CurrentUser` is `Depends(get_current_user)` (`deps.py:30-46`): it decodes the bearer token with `jwt.decode`, validates `TokenPayload`, loads the `User` with `session.get(User, token_data.sub)`, and rejects a missing or inactive user.
5. FastAPI calls `backend/app/api/routes/items.py:14-45`, `read_items(session, current_user, skip, limit)`. Defaults are `skip=0` and `limit=100`.
6. For a superuser (`current_user.is_superuser` true), lines 22-23 count every row with `select(func.count()).select_from(Item)`. Lines 24-27 select every `Item`, order by `Item.created_at` descending, then apply offset and limit.
7. For a non-superuser, lines 29-34 count only rows where `Item.owner_id == current_user.id`. Lines 35-42 apply the same owner predicate to the item query, then order descending by `created_at` and apply offset/limit. Thus the response contains only that user’s items, while a superuser’s response contains all users’ items.
8. Lines 44-45 convert each ORM `Item` to `ItemPublic` with `ItemPublic.model_validate(item)` and return `ItemsPublic(data=items_public, count=count)`. FastAPI then serializes/validates that declared response model. The contract is also recorded as `ItemsPublic` in `docs/api/openapi.json` under `/api/v1/items/`.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. Since the items router has tag `items`, the list route’s operation ID is `items-read_items` (shown in `docs/api/openapi.json`), rather than FastAPI’s verbose default. The generated SDK consequently exposes the concise `readItems` method in `frontend/src/client/sdk.gen.ts`.

If the hook were removed, FastAPI’s default operation IDs would include the function name, normalized path, and HTTP method. For the item routes they would be approximately:

- `read_items_api_v1_items__get` → generated SDK method `readItemsApiV1ItemsGet`
- `create_item_api_v1_items__post` → `createItemApiV1ItemsPost`
- `read_item_api_v1_items__id__get` → `readItemApiV1ItemsIdGet`
- `update_item_api_v1_items__id__put` → `updateItemApiV1ItemsIdPut`
- `delete_item_api_v1_items__id__delete` → `deleteItemApiV1ItemsIdDelete`

The exact TypeScript casing follows the generator’s camel-casing of those default operation IDs. This is the shortening rationale documented in `docs/ard/0005-generated-typescript-client.md`.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` declares `Item.owner_id` as a non-nullable FK to `user.id` with database-level `ondelete="CASCADE"`. Removing it would remove the database’s automatic child-row deletion: a direct database deletion of a `User` with `Item` rows would instead violate the FK, and any schema migration would need to drop/recreate the constraint without `ON DELETE CASCADE`. The checked-in migration that establishes this behavior is `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`.

There is an important distinction in this repository: `User.items` still has SQLAlchemy/SQLModel `cascade_delete=True` at `models.py:59`, `DELETE /users/{user_id}` explicitly executes `delete(Item).where(Item.owner_id == user_id)` at `backend/app/api/routes/users.py:228-230`, and `DELETE /users/me` uses ORM deletion at `users.py:141-142`. Therefore removing only the model FK option does not break those application paths immediately; it removes the DB-level protection.

No existing test actually catches that specific regression. The closest named test is `backend/tests/api/routes/test_users.py:test_delete_user_me`, but it creates and deletes a user without creating an Item or asserting child-row deletion. `test_delete_user_super_user` has the same omission, and the item tests cover item deletion/authorization, not parent deletion. A real regression test would need to create an Item for the deleted user and assert that it is gone after deleting the user.

## 4. Why `authenticate` verifies `DUMMY_HASH`

`backend/app/crud.py:45-51` first calls `get_user_by_email`. If no user exists, it still calls `verify_password(password, DUMMY_HASH)` before returning `None`. `DUMMY_HASH` at lines 40-42 is a fixed Argon2 hash. Password verification is deliberately expensive; doing it for nonexistent emails makes the nonexistent-user path take roughly as long as a real-user/wrong-password path. That prevents an attacker from using response timing to enumerate which email addresses have accounts. This is the timing-attack mitigation described in `docs/ard/0002-jwt-bearer-auth.md`.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the application-level guard in `backend/app/api/routes/items.py:48-58`, inside `read_item`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

The `CurrentUser` dependency in `backend/app/api/deps.py` authenticates the caller first; the route then permits the read only when the caller is a superuser or owns the item. The exact regression test is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`, which expects HTTP 403 and the `Not enough permissions` detail.
