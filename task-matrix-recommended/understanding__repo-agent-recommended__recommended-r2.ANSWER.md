# Codebase answers

## 1. `GET /api/v1/items/`

From the supplied frontend, `frontend/src/routes/_layout/items.tsx` calls
`getItemsQueryOptions().queryFn` (lines 12–17), which calls the generated
`ItemsService.readItems` in `frontend/src/client/sdk.gen.ts:293-300`. That
method uses the generated client from `frontend/src/client/client.gen.ts` and
sends an authenticated `GET` to `/api/v1/items/`, with `skip=0` and `limit=100`.

On the backend, the request reaches the `app` object in
`backend/app/main.py:21-25`; `app.include_router(api_router,
prefix=settings.API_V1_STR)` at line 35 supplies the `/api/v1` prefix. The
router aggregation in `backend/app/api/main.py:6-10` includes
`app.api.routes.items.router`. That router is declared in
`backend/app/api/routes/items.py:10` with prefix `/items` and tags `['items']`,
and its `@router.get("/")` operation dispatches to `read_items` at lines 13–16.

Before `read_items` runs, FastAPI resolves its `SessionDep` and `CurrentUser`
parameters. `SessionDep` is `Annotated[Session, Depends(get_db)]` in
`backend/app/api/deps.py:21-27`; `get_db` opens `Session(engine)` (where
`engine` is created in `backend/app/core/db.py:7`) and yields it. `CurrentUser`
is `Annotated[User, Depends(get_current_user)]` (`deps.py:30-49`).
`get_current_user` decodes the bearer JWT using `jwt.decode`, constructs a
`TokenPayload`, loads the `User` with `session.get(User, token_data.sub)`, and
rejects invalid tokens, missing users, or inactive users before returning the
user (`deps.py:30-46`).

`read_items` then behaves as follows (`backend/app/api/routes/items.py:14-45`):

- For a superuser (`current_user.is_superuser`), it counts all `Item` rows
  (`select(func.count()).select_from(Item)`) and selects all rows ordered by
  `Item.created_at` descending, applying `skip` and `limit`.
- For a non-superuser, it adds `where(Item.owner_id == current_user.id)` to
  both the count query and the item query; the result is therefore only that
  user's items, with the same descending timestamp order and pagination.

Each selected row is converted with `ItemPublic.model_validate` (line 44), and
the function returns `ItemsPublic(data=items_public, count=count)` (line 45).
`ItemPublic` and `ItemsPublic` are defined in `backend/app/models.py:103-113`;
FastAPI validates/serializes that response as the declared `ItemsPublic`
response model.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines `custom_generate_unique_id(route)` as
`f"{route.tags[0]}-{route.name}"`. `FastAPI(...)` installs it at line 24 via
`generate_unique_id_function=custom_generate_unique_id`. For this route, the
ID is therefore `items-read_items`: the first router tag is `items`, and the
function name is `read_items`.

The generated client is configured by `frontend/openapi-ts.config.ts:11-18`:
the SDK groups operations by tags, uses static methods, names containers
`{{name}}Service`, and removes the tag prefix from each operation name. Thus
the current operation is `ItemsService.readItems` (`frontend/src/client/sdk.gen.ts:287-300`).

If the custom generator were removed, FastAPI's default raw operation ID for
this trailing-slash path/method would be `read_items_items__get` (the default
algorithm concatenates `route.name` and `/items/`, replaces each non-word
character with `_`, then appends `_get`). With this generator's client naming
configuration, the generated TypeScript method would be normalized to
`ItemsService.readItemsItemsGet` (and its associated operation types would use
the corresponding `itemsReadItemsItemsGet...`-style names), rather than
`ItemsService.readItems`. The repository's `okf/services/backend.md:42-51`
records the client-level contrast as `readItemsItemsGet`.

## 3. Removing `ondelete="CASCADE"` from `Item.owner_id`

The declaration is `backend/app/models.py:97-99`. Removing it would stop the
SQLModel/SQLAlchemy metadata from requesting an `ON DELETE CASCADE` foreign-key
action for newly created or migrated database schemas. A direct database
delete of a `user` that still has `item.owner_id` rows would then violate the
non-null foreign key instead of deleting those items. The already committed
Alembic migration `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:20-27`
is what creates the database constraint with `ondelete='CASCADE'`.

In this current application, the ordinary user-delete paths have additional
protection: `User.items` has `cascade_delete=True` in `models.py:59`,
`delete_user_me` calls `session.delete(current_user)` (`backend/app/api/routes/users.py:132-143`),
and admin `delete_user` explicitly deletes matching `Item` rows before the
user (`users.py:214-231`).

There is no existing test function that would actually catch removal of the
database-level `ondelete`: `backend/tests/api/routes/test_users.py:test_delete_user_me`
only deletes a user and asserts the user row is absent; it neither creates nor
checks an owned item, and the ORM relationship cascade would still handle that
path. `test_delete_user_super_user` similarly creates no item. A regression
test would need to create an item for a user, delete the user through a path
that relies on the database FK cascade (or issue a direct DB delete), and then
assert the item is gone.

## 4. Why `authenticate` verifies `DUMMY_HASH`

`backend/app/crud.py:40-60` defines `DUMMY_HASH` as a fixed Argon2 hash and,
when `get_user_by_email` at lines 34–37 returns no user, calls
`verify_password(password, DUMMY_HASH)` at lines 47–50 before returning `None`.
`verify_password` delegates to `PasswordHash.verify_and_update` in
`backend/app/core/security.py:29-32`.

The result is intentionally discarded. Argon2 verification has comparable cost
to verification against a real stored hash, so nonexistent-email login
attempts take roughly the same password-check path as wrong-password attempts
for existing users. Without it, the faster nonexistent-user response would
enable timing-based email/account enumeration.

## 5. Item-read ownership mechanism

The exact mechanism is the inline guard in
`backend/app/api/routes/items.py:53-57`, inside `read_item`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

Because `current_user` is supplied by the `CurrentUser` dependency in
`backend/app/api/deps.py:30-49`, a non-superuser whose ID differs from
`item.owner_id` receives 403 and the item is not returned. This is
application-level authorization, not PostgreSQL row-level security. The exact
existing test for it is
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`
(lines 55–65), which expects the 403 and the `Not enough permissions` detail.
