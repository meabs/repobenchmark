# Answers

## 1. `GET /api/v1/items/`

1. `frontend/src/client/sdk.gen.ts:293`, `ItemsService.readItems`, is the generated client method (when called by the UI, `frontend/src/routes/_layout/items.tsx` calls it with `skip: 0, limit: 100`). The checked-in contract in `docs/api/openapi.json` identifies this operation as `items-read_items`.
2. `backend/app/main.py:21-25` creates the FastAPI app, and `backend/app/main.py:35` mounts `api_router` under `settings.API_V1_STR`, which is `/api/v1`.
3. `backend/app/api/main.py:6-10` builds `api_router` and includes `items.router`. `backend/app/api/routes/items.py:10` defines that router with prefix `/items` and tag `items`; `@router.get("/")` at lines 13-14 therefore matches `/api/v1/items/` and dispatches to `read_items`.
4. Before `read_items` runs, FastAPI resolves `SessionDep` and `CurrentUser` from `backend/app/api/deps.py`. `get_db` (lines 24-26) yields a SQLModel `Session(engine)`. `get_current_user` (lines 34-52) decodes the bearer token with `jwt.decode`, validates it as `TokenPayload`, loads the `User` by `token_data.sub`, and rejects invalid credentials (403), a missing user (404), or an inactive user (400).
5. `backend/app/api/routes/items.py:14-45`, `read_items`, branches on `current_user.is_superuser`:
   - Superuser: counts all `Item` rows (`select(func.count()).select_from(Item)`) and selects all items, ordered by `Item.created_at` descending, then applies `skip` and `limit`.
   - Non-superuser: counts only rows with `Item.owner_id == current_user.id`, and selects only those rows with the same ownership predicate, descending creation order, and pagination.
6. The selected ORM rows are converted at line 44 with `ItemPublic.model_validate(item)`, then line 45 returns `ItemsPublic(data=items_public, count=count)`. FastAPI serializes that `ItemsPublic` response model.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. For the items list route, the tag is `items` and the function name is `read_items`, so the OpenAPI operation ID is `items-read_items` (as shown in `docs/api/openapi.json:731`). `main.py:24` installs this function as FastAPI's `generate_unique_id_function`.

If it were removed, FastAPI would use its default path/method-based ID. For this route that is `read_items_items__get` (function name plus `/items/`, normalized and suffixed with `get`), rather than `items-read_items`. The generated Hey API client would consequently expose the operation under the camel-cased name `readItemsItemsGet` instead of `ItemsService.readItems` (the existing generated method is at `frontend/src/client/sdk.gen.ts:293`).

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` declares `Item.owner_id` as a non-null foreign key to `user.id` with `ondelete="CASCADE"`. The matching database constraint is also established by migration `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`.

Without that database cascade, deleting a user that still owns items would violate the non-null foreign-key constraint and fail (typically as a database integrity error), leaving the user deletion unsuccessful. This affects `backend/app/api/routes/users.py:132-143`, `delete_user_me`, which calls `session.delete(current_user)` without first deleting that user's items. The admin route `delete_user` is different: `users.py:228-230` explicitly deletes matching `Item` rows before deleting the user, so that path does not depend on the database cascade.

The relevant existing test function is `backend/tests/api/routes/test_users.py:test_delete_user_me`. Important precision: as currently written, it creates only a user and does not create an owned item, so it would not actually catch this regression. A regression-catching version would create an Item for that user before the DELETE; no current test does that. `test_delete_user_super_user` is likewise protected by the route's explicit item deletion.

## 4. Why verify `DUMMY_HASH`

`backend/app/crud.py:45-51`, `authenticate`, calls `verify_password(password, DUMMY_HASH)` when `get_user_by_email` returns no user, then returns `None`. `DUMMY_HASH` at lines 40-42 is a real Argon2 hash, so the missing-user path performs the same expensive password-hash verification work as the known-user path at line 52. This reduces timing differences that could reveal whether an email address exists (email/user enumeration). The result is deliberately ignored because there is no user to authenticate.

## 5. Non-owner read protection

The exact mechanism is the inline ownership guard in `backend/app/api/routes/items.py:48-55`, inside `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

`read_item` first loads the row with `session.get(Item, id)` and returns 404 if absent. For an existing row, the guard permits a superuser or the owning user and returns 403 for every other user. The regression/behavior test is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`.
