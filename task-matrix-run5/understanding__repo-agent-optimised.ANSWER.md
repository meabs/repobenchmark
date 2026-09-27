# Codebase answers

## 1. `GET /api/v1/items/`

The request is registered and handled in this order:

1. `backend/app/main.py:21-25` constructs the FastAPI `app`, and
   `backend/app/main.py:35` mounts `api_router` under `settings.API_V1_STR`
   (normally `/api/v1`).
2. `backend/app/api/main.py:10` includes `items.router` in `api_router`.
   `backend/app/api/routes/items.py:10` defines that router with prefix
   `/items` and tag `items`; `read_items` at lines 13-16 registers `GET /`.
   Together these produce `GET /api/v1/items/`.
3. FastAPI resolves `SessionDep` and `CurrentUser` in
   `backend/app/api/routes/items.py:14-15`. `SessionDep` is the annotation
   `Annotated[Session, Depends(get_db)]` from `backend/app/api/deps.py:21-26`;
   `get_db` opens `Session(engine)`, yields it, and closes it when the request
   finishes. `CurrentUser` is `Annotated[User, Depends(get_current_user)]` at
   `deps.py:49`.
4. `get_current_user` in `backend/app/api/deps.py:30-46` receives the bearer
   token through `reusable_oauth2` (`deps.py:16-18`), calls
   `jwt.decode(token, settings.SECRET_KEY, algorithms=[security.ALGORITHM])`
   (`deps.py:32-34`), validates the payload as `TokenPayload` (`deps.py:35`),
   loads the `User` with `session.get(User, token_data.sub)` (`deps.py:41`),
   rejects a missing user with 404 and an inactive user with 400, and returns
   the active `User`. Token/decode or payload-validation failures become 403.
5. FastAPI calls `read_items` in `backend/app/api/routes/items.py:14-45`.
   `skip` defaults to 0 and `limit` to 100. It counts and selects using
   SQLModel statements, orders by `Item.created_at` descending, applies the
   offset/limit, validates each result into `ItemPublic` at line 44, and
   returns `ItemsPublic(data=items_public, count=count)` at line 45. The
   declared response model is `ItemsPublic`.

The branch at `items.py:21` is the authorization difference:

- A superuser counts all rows (`select(func.count()).select_from(Item)`,
  lines 22-23) and selects all Items ordered newest first (lines 24-27).
- A non-superuser counts only rows whose `Item.owner_id == current_user.id`
  (lines 29-34), and the item query has the same owner predicate before its
  ordering/pagination (lines 35-42). Thus the returned `count` and `data` are
  both owner-scoped. The response conversion exposes `ItemPublic`, not the
  raw table object.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. The
FastAPI constructor passes it as `generate_unique_id_function` at line 24.
For this route, the tag is `items` and the function name is `read_items`, so
the OpenAPI operation ID is `items-read_items` (as shown in
`docs/api/openapi.json`), and the generated client exposes
`ItemsService.readItems` with types such as `itemsReadItemsData`.

If the custom function were removed, FastAPI's default generator would use the
route name plus the full path, sanitize non-word characters to underscores,
and append the HTTP method. For this mounted route that is
`read_items_api_v1_items__get`. The generated TypeScript operation-oriented
names would consequently be based on that ID, e.g.
`readItemsApiV1ItemsGet` and `readItemsApiV1ItemsGetData`, rather than
`readItems` / `itemsReadItemsData`. The exact generated spelling is determined
by the configured OpenAPI TypeScript generator, but the important change is
that the path-derived `apiV1ItemsGet` suffix appears.

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:97-99`, on the foreign key from
`item.owner_id` to `user.id`. The checked-in migration
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`
creates the database foreign key with `ondelete='CASCADE'`.

If the model declaration were removed and the database were migrated to match,
the database would no longer cascade a direct parent-User deletion to its
Items; PostgreSQL's foreign-key action would reject the parent deletion while
dependent Items remain. It would also make the model and migration/schema
contract inconsistent until a migration changed the existing constraint.
The ORM-side `User.items` relationship still has `cascade_delete=True` at
`models.py:59`, and `users.py:228-230` explicitly bulk-deletes Items before
an admin deletes a User, so those application paths are not a reliable test of
the database FK action.

There is no existing test function that catches this specific regression. In
particular, `backend/tests/api/routes/test_users.py:test_delete_user_me`
(lines 420-449) deletes a user but creates no Item, and
`test_delete_user_super_user` (lines 463-480) exercises the route that
explicitly deletes Items first. The fixture in `backend/tests/conftest.py:20-24`
also deletes all Items before Users. A test that creates an Item, deletes its
User through a path relying on the database FK, and asserts the Item is gone
would be needed.

## 4. The `DUMMY_HASH` verification

`backend/app/crud.py:45-60` first looks up the user with
`get_user_by_email` (`crud.py:34-37`). When no row is found, lines 48-50 still
call `verify_password(password, DUMMY_HASH)` and then return `None`.
`DUMMY_HASH` at lines 40-42 is a fixed Argon2 hash. Since password verification
has a deliberately expensive, roughly fixed cost, doing the same work for a
missing account makes nonexistent-email login attempts take about as long as
wrong-password attempts for real accounts. That prevents response timing from
enumerating which email addresses exist. It does not authenticate the request:
the branch always returns `None`.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the application-level guard in
`backend/app/api/routes/items.py:53-58`, inside `read_item`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

`CurrentUser` is resolved first through `get_current_user` in
`backend/app/api/deps.py`, so the endpoint also requires a valid bearer token.
The non-owner behavior is specifically the `not current_user.is_superuser`
and `item.owner_id != current_user.id` predicate, which returns 403; a
superuser bypasses it. The regression test for this exact endpoint is
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`
(lines 55-65).
