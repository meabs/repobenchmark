# Answers

## 1. `GET /api/v1/items/`

The request reaches the `FastAPI` instance `app` in `backend/app/main.py:21-25`.
That instance mounts `api_router` at `settings.API_V1_STR` (`/api/v1`) in
`backend/app/main.py:35`. `backend/app/api/main.py:6-10` has included
`items.router`; that router is declared in `backend/app/api/routes/items.py:10` as
`prefix="/items"`, `tags=["items"]`, and its `GET /` operation is
`read_items` (`backend/app/api/routes/items.py:13-16`). The current OpenAPI
operation ID is `items-read_items` (`docs/api/openapi.json:724-731`).

Before `read_items` runs, FastAPI resolves its dependencies:

1. `session: SessionDep` (`backend/app/api/deps.py:26`) calls `get_db`
   (`backend/app/api/deps.py:21-24`), which opens a SQLModel `Session(engine)`;
   `engine` is imported from `backend/app/core/db.py`.
2. `current_user: CurrentUser` (`backend/app/api/deps.py:49`) calls
   `get_current_user` (`backend/app/api/deps.py:30-46`). Its `TokenDep` comes
   from `OAuth2PasswordBearer` configured at `backend/app/api/deps.py:16-18`.
   `get_current_user` decodes the bearer JWT with `settings.SECRET_KEY` and
   `security.ALGORITHM` (`HS256` in `backend/app/core/security.py:19`), validates
   `TokenPayload`, loads `User` with `session.get(User, token_data.sub)`, and
   rejects an invalid token (403), missing user (404), or inactive user (400).

`read_items` (`backend/app/api/routes/items.py:14-45`) then branches on
`current_user.is_superuser`:

- Superuser: counts every row with `select(func.count()).select_from(Item)` and
  selects every `Item`, ordered by `created_at` descending, then applies
  `offset(skip)` and `limit(limit)` (`items.py:21-27`).
- Non-superuser: counts only rows where `Item.owner_id == current_user.id`
  (`items.py:29-34`), and selects only those same-owned rows with the same
  descending ordering and pagination (`items.py:35-42`).

Finally, each ORM `Item` is converted to `ItemPublic` with
`ItemPublic.model_validate` (`items.py:44`), and the route returns
`ItemsPublic(data=items_public, count=count)` (`items.py:45`). FastAPI serializes
that `response_model=ItemsPublic`; the schema is defined in
`backend/app/models.py:103-112`.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`. The app
passes it as `generate_unique_id_function` at `main.py:21-25`, so the items
operation IDs are stable, readable IDs such as `items-read_items`; the generated
client exposes these as `ItemsService.readItems`, `createItem`, `readItem`,
`updateItem`, and `deleteItem` (see `frontend/src/client/sdk.gen.ts:293-367`).

If the argument were removed, FastAPI's default (verified from the installed
FastAPI version) builds the ID from the route function name, sanitized path, and
HTTP method. The item operation IDs would be:

| Route function | Default operation ID | Generated client method |
|---|---|---|
| `read_items` | `read_items_items__get` | `readItemsItemsGet` |
| `create_item` | `create_item_items__post` | `createItemItemsPost` |
| `read_item` | `read_item_items__id__get` | `readItemItemsIdGet` |
| `update_item` | `update_item_items__id__put` | `updateItemItemsIdPut` |
| `delete_item` | `delete_item_items__id__delete` | `deleteItemItemsIdDelete` |

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:97-99`. It describes the database
foreign key from `item.owner_id` to `user.id`; the migration that installs the
database behavior is `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`.
Without that database-level cascade, a direct database deletion of a User that
still has Item rows would fail with a foreign-key violation instead of deleting
the child Items.

However, the current application has two additional deletion paths: deleting a
User through `delete_user_me` (`backend/app/api/routes/users.py:132-143`) uses
`User.items = Relationship(..., cascade_delete=True)` (`models.py:59`), and the
superuser `delete_user` route explicitly deletes Items first (`users.py:228-231`).
Consequently, removing only the model declaration does not make either current
route test fail, and the existing schema would not change until a migration is
applied.

There is no existing test function that actually catches this regression: neither
`test_delete_user_me` nor `test_delete_user_super_user` creates an Item before
deleting the User (`backend/tests/api/routes/test_users.py:420-480`). The exact
closest test is `test_delete_user_me`, but as written it asserts only that the User
row disappears. A real regression test would need to create an Item owned by that
User, delete the User, and assert the Item is gone (or test direct DB deletion).

## 4. `DUMMY_HASH`

`backend/app/crud.py:45-60` first looks up the email. If no User exists, it still
calls `verify_password(password, DUMMY_HASH)` at `crud.py:47-50`, then returns
`None`. `verify_password` delegates to the deliberately expensive Argon2/bcrypt
password verifier in `backend/app/core/security.py:29-32`. This keeps the
nonexistent-email path's work and timing comparable to the existing-user path,
preventing an attacker from using response timing to enumerate registered email
addresses. The dummy value is documented as a random Argon2 hash at
`crud.py:40-42`; it is not used as a real credential.

## 5. Reading an Item by ID

The exact mechanism is the application-level guard in
`backend/app/api/routes/items.py`, function `read_item`, lines 53-58:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

The route has `CurrentUser` dependency injection (`items.py:48-49`), so the
bearer token is resolved by `get_current_user` before this guard. The decisive
pattern is `not current_user.is_superuser and item.owner_id != current_user.id`:
superusers may read any existing Item, while a non-owner receives HTTP 403.
