# Answers

## 1. `GET /api/v1/items/`

The request path is:

1. `backend/app/main.py`: module construction creates `app = FastAPI(...)` and
   calls `app.include_router(api_router, prefix=settings.API_V1_STR)`. `settings.API_V1_STR`
   is `/api/v1` in `backend/app/core/config.py`.
2. `backend/app/api/main.py`: `api_router` includes `items.router`.
   `backend/app/api/routes/items.py` defines that router with prefix `/items` and
   `tags=["items"]`; its `@router.get("/", response_model=ItemsPublic)` route is
   `read_items`.
3. FastAPI resolves `SessionDep` and `CurrentUser` from
   `backend/app/api/deps.py`. `get_db` opens `Session(engine)`; `engine` is the
   SQLModel engine created in `backend/app/core/db.py`. `get_current_user` decodes
   the bearer token with `jwt.decode`, validates `TokenPayload`, loads the user
   with `session.get(User, token_data.sub)`, and rejects an invalid, missing, or
   inactive user before returning the `User`.
4. FastAPI calls `backend/app/api/routes/items.py:read_items(session,
   current_user, skip, limit)`. `skip` defaults to `0` and `limit` to `100`.
5. For a superuser (`current_user.is_superuser` true), `read_items` counts all
   rows with `select(func.count()).select_from(Item)`, then selects all `Item`
   rows ordered by `col(Item.created_at).desc()`, applying `offset(skip)` and
   `limit(limit)`.
6. For a non-superuser, both the count query and item query add
   `where(Item.owner_id == current_user.id)`. The item query has the same
   descending `created_at` ordering and pagination, so neither the count nor the
   returned data includes another user's items.
7. `read_items` converts each result with `ItemPublic.model_validate(item)` and
   returns `ItemsPublic(data=items_public, count=count)`. FastAPI serializes that
   response according to `ItemPublic`/`ItemsPublic` from `backend/app/models.py`.

The current OpenAPI operation is documented as `items-read_items` in
`docs/api/openapi.json`; the generated browser client is
`frontend/src/client/sdk.gen.ts:ItemsService.readItems`, which calls the same URL.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`, and
`backend/app/main.py:24` installs it as FastAPI's
`generate_unique_id_function`. Thus the item operation IDs are, for example,
`items-read_items` and `items-read_item`; hey-api generates the concise methods
`ItemsService.readItems` and `ItemsService.readItem`.

If the function were removed, FastAPI's default generator would use
`route.name + route.path_format`, replace non-word characters with `_`, and append
the lower-case HTTP method. The item operation IDs would consequently be:

- `read_items_api_v1_items__get`
- `create_item_api_v1_items__post`
- `read_item_api_v1_items_id_get`
- `update_item_api_v1_items_id_put`
- `delete_item_api_v1_items_id_delete`

The generated TypeScript methods would therefore be path-derived names such as
`readItemsApiV1ItemsGet`, `createItemApiV1ItemsPost`,
`readItemApiV1ItemsIdGet`, `updateItemApiV1ItemsIdPut`, and
`deleteItemApiV1ItemsIdDelete` (instead of the current concise names).

## 3. Removing `Item.owner_id`'s `ondelete="CASCADE"`

`backend/app/models.py:97-99` declares the database foreign key from
`item.owner_id` to `user.id` with `ondelete="CASCADE"`. Removing it would remove
the database-level cascade when the constraint is migrated: a direct SQL delete
of a User while owned Items still exist would be rejected by the foreign-key
constraint instead of deleting those Items.

There is an important repository-specific qualification: no existing test actually
asserts that deleting a User also deletes an Item. `test_delete_user_me` in
`backend/tests/api/routes/test_users.py` only creates/deletes a User and checks
that the User row is gone; `test_delete_user_super_user` uses
`backend/app/api/routes/users.py:delete_user`, which explicitly executes
`delete(Item).where(col(Item.owner_id) == user_id)` before deleting the User.
Also, `User.items` still has `cascade_delete=True` in `models.py`, so the
`delete_user_me` ORM path retains ORM-level cascade behavior if only
`Item.owner_id.ondelete` is removed. Therefore the exact answer is: no existing
test function would catch this model-only regression; `test_delete_user_me` is
the closest deletion test, but it does not create an Item or assert its deletion.

The intended DB-level protection is represented by the Alembic migration
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py`,
which creates the FK with `ondelete='CASCADE'`.

## 4. Why `authenticate` verifies `DUMMY_HASH`

In `backend/app/crud.py:45-60`, `authenticate` first calls
`get_user_by_email`. If no user exists, it still calls
`verify_password(password, DUMMY_HASH)` and then returns `None`. `verify_password`
delegates to `pwdlib`'s Argon2/bcrypt verifier in `backend/app/core/security.py`.

That deliberately performs the expensive password-hash work on the nonexistent-
user path. Without it, login for an unknown email would be measurably faster than
login for a known email with a wrong password, enabling user/email enumeration by
timing. `DUMMY_HASH` is a fixed Argon2 hash used only to equalize that work; it is
never used as a credential or returned.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the conditional in
`backend/app/api/routes/items.py:56-57`, inside `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

`read_item` first loads the row with `session.get(Item, id)` and returns 404 if it
does not exist; only then does this ownership check run. The regression/behavior
test is `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`,
which sends a normal user's token for an Item created for another random user and
asserts HTTP 403 with that detail.
