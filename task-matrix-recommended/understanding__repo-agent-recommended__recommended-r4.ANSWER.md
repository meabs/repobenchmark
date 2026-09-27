# Codebase answers

## 1. `GET /api/v1/items/`

1. `backend/app/main.py:21-25` constructs the FastAPI `app`; `main.py:35` mounts
   `api_router` under `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py:6-10` builds `api_router` and includes
   `items.router`.
3. `backend/app/api/routes/items.py:10` defines that router with prefix `/items`
   and tag `items`; `items.py:13-16` registers `read_items` for `GET /`.
   Together these produce `GET /api/v1/items/`.
4. Before `read_items` runs, FastAPI resolves its `SessionDep` and `CurrentUser`
   parameters (`items.py:14-16`). `SessionDep` is
   `Annotated[Session, Depends(get_db)]` in `backend/app/api/deps.py:21-26`;
   `get_db` opens `Session(engine)` and yields it. `CurrentUser` is
   `Annotated[User, Depends(get_current_user)]` (`deps.py:30-49`).
5. `get_current_user` (`deps.py:30-46`) decodes the bearer token with
   `jwt.decode(..., settings.SECRET_KEY, algorithms=[security.ALGORITHM])`,
   validates it as `TokenPayload`, loads the subject with `session.get(User,
   token_data.sub)`, and rejects an invalid token (403), missing user (404), or
   inactive user (400). It returns the `User` object, including `is_superuser`.
6. `read_items` (`items.py:14-45`) branches on `current_user.is_superuser`.
   For a superuser, it counts all `Item` rows (`items.py:21-23`), then selects
   all Items ordered by `created_at DESC`, applying `skip` and `limit`
   (`items.py:24-27`). For a non-superuser, both the count and select add
   `Item.owner_id == current_user.id` (`items.py:28-42`), so the count and data
   contain only that user’s Items; the same ordering and pagination apply.
7. Each selected ORM Item is converted to `ItemPublic` at `items.py:44`, and
   `ItemsPublic(data=items_public, count=count)` is returned at `items.py:45`.
   FastAPI serializes it according to `response_model=ItemsPublic` declared at
   `items.py:13`.

`crud.py` is not involved in this GET path; it is used by item creation and
authentication elsewhere.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines `custom_generate_unique_id(route)` as:

```python
return f"{route.tags[0]}-{route.name}"
```

`main.py:21-25` passes it to `FastAPI(generate_unique_id_function=...)`. Thus
the items list operation ID is `items-read_items` (also visible in
`docs/api/openapi.json`), and the frontend generator strips the tag prefix using
the `methodName` function in `frontend/openapi-ts.config.ts:11-18`, producing
`ItemsService.readItems` in `frontend/src/client/sdk.gen.ts:287-300`.

If the custom function were removed, FastAPI’s default path/method-derived IDs
would be used. The generated `ItemsService` method names would consequently be
the verbose forms `readItemsItemsGet`, `createItemItemsPost`,
`readItemItemsIdGet`, `updateItemItemsIdPut`, and `deleteItemItemsIdDelete`
(rather than `readItems`, `createItem`, `readItem`, `updateItem`, and
`deleteItem`).

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-100` declares `Item.owner_id` as a non-nullable FK to
`user.id` with `ondelete="CASCADE"`. Removing that argument removes the
database-level action from newly generated schema/migrations: deleting a User
directly in the database would leave referencing Items and would fail with a
foreign-key violation instead of deleting those Items.

It does not break the two application deletion routes in the current code:

- `backend/app/models.py:59` still has the ORM relationship
  `cascade_delete=True`, so a SQLModel/SQLAlchemy ORM deletion can cascade.
- `backend/app/api/routes/users.py:214-231`, specifically `delete_user`,
  explicitly executes `DELETE FROM item WHERE owner_id == user_id` at lines
  228-229 before deleting the User.

There is no existing test function that would catch the stated FK regression.
`backend/tests/api/routes/test_users.py:test_delete_user_me` exercises
`session.delete(current_user)` but creates no Item, while
`test_delete_user_super_user` also creates no Item and the admin route manually
deletes Items. A regression test would need to create an Item for a User, delete
that User through a path that relies on the database FK, and assert the Item is
gone (or that deletion does not fail).

## 4. `DUMMY_HASH`

`backend/app/crud.py:45-60` first calls `get_user_by_email`. When no User is
found (`crud.py:47`), it still calls `verify_password(password, DUMMY_HASH)` at
line 50, then returns `None`. `verify_password` is the Argon2/bcrypt-backed
`password_hash.verify_and_update` wrapper in `backend/app/core/security.py:29-32`.

The call equalizes the expensive password-verification work for nonexistent and
existing email addresses. Without it, nonexistent-email logins would return
faster than real-email/wrong-password logins, creating a timing side channel for
email/account enumeration. The result is intentionally discarded because only
the timing work matters.

## 5. Reading another owner’s Item

The exact mechanism is the inline authorization guard in
`backend/app/api/routes/items.py:53-58`, inside `read_item`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

The `CurrentUser` dependency at `items.py:49` supplies the authenticated User;
the second condition is the exact non-owner check. Thus an existing Item owned
by another non-superuser returns HTTP 403, while a superuser bypasses the guard.
The existing test `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`
asserts this behavior.
