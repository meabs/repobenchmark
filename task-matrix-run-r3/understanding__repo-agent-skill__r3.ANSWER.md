# Answers

## 1. `GET /api/v1/items/`

The application-side path is:

1. `backend/app/main.py:21-25` constructs `app` and installs
   `custom_generate_unique_id`; `backend/app/main.py:35` mounts `api_router` at
   `settings.API_V1_STR` (`/api/v1`).
2. `backend/app/api/main.py:10` includes `items.router`. The router in
   `backend/app/api/routes/items.py:10` has prefix `/items` and tag `items`, and
   `read_items` at lines 13-16 registers `GET /` with response model
   `ItemsPublic`. Together these produce `/api/v1/items/`.
3. FastAPI resolves `SessionDep` and `CurrentUser` in
   `backend/app/api/deps.py`. `SessionDep` calls `get_db` (lines 21-23), which
   opens `Session(engine)` from `backend/app/core/db.py` and yields it.
   `CurrentUser` calls `get_current_user` (lines 30-46): it decodes the bearer
   token with `jwt.decode(..., settings.SECRET_KEY, algorithms=[security.ALGORITHM])`,
   validates `TokenPayload`, loads the `User` with `session.get(User,
   token_data.sub)`, and rejects invalid, missing, or inactive users.
4. FastAPI calls `read_items` in `backend/app/api/routes/items.py:13-45`.
   The superuser branch (lines 21-27) counts every `Item`, then selects every
   item ordered by `Item.created_at` descending, applying `skip` and `limit`.
   The non-superuser branch (lines 28-42) counts only rows where
   `Item.owner_id == current_user.id` and applies that same predicate to the
   ordered, paginated item query.
5. Lines 44-45 validate each returned ORM object as `ItemPublic` and return
   `ItemsPublic(data=items_public, count=count)`. The OpenAPI contract in
   `docs/api/openapi.json` describes the same response as `ItemsPublic`.

Thus a superuser receives the global count and page of items; a non-superuser
receives only their own count and page. Both pages are ordered newest-first.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. The items
list route therefore has OpenAPI operation ID `items-read_items` (confirmed in
`docs/api/openapi.json`), and the generated client exposes
`ItemsService.readItems` in `frontend/src/client/sdk.gen.ts:287-300`.

If the custom function were removed, FastAPI's default unique-ID generator would
use the route name plus a sanitized path and HTTP method. For this endpoint the
operation ID would be:

```
read_items_api_v1_items__get
```

With the current Hey API generator's operation-ID-to-TypeScript naming, the
corresponding service method would be `ItemsService.readItemsApiV1ItemsGet`
(and the generated types would similarly be prefixed from that operation ID),
rather than `ItemsService.readItems`. The other item methods would analogously
gain their path/method suffixes, e.g. `readItemApiV1ItemsIdGet`.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-100` declares `Item.owner_id` as a non-nullable FK to
`user.id` with `ondelete="CASCADE"`. The database migration
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:20-27`
also installs the PostgreSQL `ON DELETE CASCADE` constraint.

If the model change were accompanied by a schema migration that removed the
database cascade, a direct SQL deletion of a `User` that still had `Item` rows
would violate the FK instead of deleting those rows. In this application,
however, the two user-deletion paths also matter: `User.items` has
`cascade_delete=True` in `models.py:59`, `delete_user_me` calls
`session.delete(current_user)` at `backend/app/api/routes/users.py:132-143`, and
the admin `delete_user` explicitly deletes `Item` rows first at lines 214-231.
So removing only the model declaration does not immediately break the existing
app (and the already-applied migration still has the DB cascade); removing the
DB constraint would mainly remove the database-level safety/net behavior.

There is no existing test function that actually catches this regression:
`backend/tests/api/routes/test_users.py:test_delete_user_me` (lines 420-449) is
the closest candidate, but it creates a user with no item and asserts only that
the user row is gone. `test_delete_user_super_user` likewise creates no item.
An effective regression test would need to create an Item for the deleted user
and assert that the Item is gone (or that direct deletion has the intended
cascade behavior).

## 4. Dummy-hash verification

`backend/app/crud.py:45-60` first looks up the email. When no user is found,
lines 48-50 still call `verify_password(password, DUMMY_HASH)` and then return
`None`. `DUMMY_HASH` at lines 40-42 is a fixed Argon2 hash of a random password.
`verify_password` delegates to `PasswordHash.verify_and_update` in
`backend/app/core/security.py:29-32`.

Argon2 verification is deliberately expensive. Performing it for nonexistent
accounts makes the nonexistent-email path take approximately the same work as
the wrong-password path for a real account, preventing an attacker from using
response timing to enumerate registered email addresses. The result is ignored;
the call exists for timing equalization, not authentication.

## 5. Reading another user's item

The exact guard is in `backend/app/api/routes/items.py:48-58`, inside
`read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

The function first loads the row with `session.get(Item, id)` and returns 404 if
it is absent (lines 53-55). For an existing row, the guard permits a superuser or
the matching owner and otherwise returns 403. The matching existing test is
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`
(lines 55-65).
