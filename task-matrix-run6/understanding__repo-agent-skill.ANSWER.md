# Answers

## 1. `GET /api/v1/items/` request trace

1. `backend/app/main.py:21-25` constructs the `FastAPI` instance, and line 35
   calls `app.include_router(api_router, prefix=settings.API_V1_STR)`. The
   configured prefix is `/api/v1`.
2. `backend/app/api/main.py:6-10` builds `api_router` and includes
   `items.router`.
3. `backend/app/api/routes/items.py:10` defines that router with prefix
   `/items` and tag `items`; line 13 registers `GET /` with
   `read_items` (line 14), so the complete path is `/api/v1/items/`.
4. Before `read_items` runs, FastAPI resolves its dependencies at
   `backend/app/api/routes/items.py:15`: `SessionDep` comes from
   `backend/app/api/deps.py:26` and invokes `get_db` (lines 21-23), which
   yields a `sqlmodel.Session(engine)`; `CurrentUser` comes from
   `backend/app/api/deps.py:49` and invokes `get_current_user` (line 30).
5. `get_current_user` obtains the bearer token through
   `reusable_oauth2` (`backend/app/api/deps.py:16-18`), decodes it with
   `jwt.decode` using `settings.SECRET_KEY` and `security.ALGORITHM` (lines
   31-35), validates it as `TokenPayload`, loads the user with
   `session.get(User, token_data.sub)` (line 41), rejects a missing user with
   404 and an inactive user with 400, and returns the `User` (lines 42-46).
6. `read_items` (`backend/app/api/routes/items.py:14-45`) branches on
   `current_user.is_superuser` (line 21).

   - For a superuser, it counts every `Item` with
     `select(func.count()).select_from(Item)` (lines 22-23), then selects all
     Items ordered by `created_at` descending and applies `offset(skip)` and
     `limit(limit)` (lines 24-27).
   - For a non-superuser, it counts only rows whose `Item.owner_id ==
     current_user.id` (lines 29-34), and the item query has the same ownership
     predicate before the same descending order, offset, and limit (lines
     35-42).

7. Each returned ORM `Item` is converted with `ItemPublic.model_validate` at
   line 44. The function returns `ItemsPublic(data=items_public, count=count)`
   at line 45; FastAPI applies the declared `response_model=ItemsPublic` from
   line 13 to serialize the response.

Thus, superusers receive the paginated global item set and global count;
non-superusers receive only their own paginated items and their own-item count.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines:

```python
def custom_generate_unique_id(route: APIRoute) -> str:
    return f"{route.tags[0]}-{route.name}"
```

`backend/app/main.py:24` passes it as FastAPI's
`generate_unique_id_function`. It takes the first route tag (`items`) and the
Python endpoint function name (`read_items`), producing the operation ID
`items-read_items`. The checked-in OpenAPI confirms this at
`docs/api/openapi.json:731`, and the generated client consequently exposes
`ItemsService.readItems` (`frontend/src/client/sdk.gen.ts:293-300`).

If the custom function were removed, FastAPI's default generator would combine
the route function name, path format, and first HTTP method, replacing
non-word characters with underscores. For the five item routes, the operation
IDs and corresponding generated `ItemsService` method names would be:

| Route | Default operation ID | TypeScript method |
|---|---|---|
| `GET /items/` (`read_items`) | `read_items_items__get` | `readItemsItemsGet` |
| `POST /items/` (`create_item`) | `create_item_items__post` | `createItemItemsPost` |
| `GET /items/{id}` (`read_item`) | `read_item_items__id__get` | `readItemItemsIdGet` |
| `PUT /items/{id}` (`update_item`) | `update_item_items__id__put` | `updateItemItemsIdPut` |
| `DELETE /items/{id}` (`delete_item`) | `delete_item_items__id__delete` | `deleteItemItemsIdDelete` |

The method names are the generator's camel-cased forms of those default
operation IDs; the custom IDs deliberately keep the client names short.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` declares `Item.owner_id` as a non-nullable
foreign key to `user.id` with database-level `ondelete="CASCADE"`. The matching
Alembic change is in
`backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`.
Removing it would remove the database-level rule that deletes an owner's Item
rows when the parent User row is deleted directly at the database level.
Otherwise the FK would reject the parent deletion (or leave orphan behavior
depending on how the deletion is performed), rather than allowing the database
to cascade.

The relevant existing test is
`backend/tests/api/routes/test_users.py:test_delete_user_me` (line 420), whose
route calls `session.delete(current_user)` in
`backend/app/api/routes/users.py:132-143`. However, the current test creates no
Item and only asserts that the User disappears, so it would not actually catch
an Item-cascade regression as written. The application also has ORM-level
`Relationship(..., cascade_delete=True)` at `models.py:59`, and the admin
`delete_user` route explicitly deletes Items at `users.py:228-230`; those are
separate from the database FK option.

## 4. Why verify `DUMMY_HASH` for an unknown user

`backend/app/crud.py:45-51` first looks up the email. If no `User` exists, it
still calls `verify_password(password, DUMMY_HASH)` before returning `None`.
`verify_password` (`backend/app/core/security.py:29-32`) performs the real
Argon2/bcrypt verification work. Running that expensive work on the missing-user
path makes login responses take approximately the same time for “unknown email”
and “known email with a bad password”. Without it, attackers could use timing
differences to enumerate registered email addresses. The result is intentionally
discarded; `DUMMY_HASH` is only a timing-equalization hash.

## 5. Exact item-read ownership mechanism

The mechanism is the explicit application check in
`backend/app/api/routes/items.py:48-58`, inside `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

The function first loads the row with `session.get(Item, id)` and returns 404 if
it does not exist (lines 53-55). Only after that does the ownership predicate
run; therefore a non-owner gets 403, while a superuser bypasses the owner-ID
comparison. This is application-enforced authorization, not PostgreSQL
row-level security or a router dependency. The exact regression test is
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`
(line 55), which expects the 403 and `Not enough permissions` detail.
