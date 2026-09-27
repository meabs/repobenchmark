# Answers

## 1. `GET /api/v1/items/`

1. `backend/app/main.py:21-25` constructs the FastAPI `app`, installs
   `custom_generate_unique_id`, and `backend/app/main.py:35` mounts `api_router`
   under `settings.API_V1_STR` (normally `/api/v1`).
2. `backend/app/api/main.py:6-10` builds `api_router` and includes
   `items.router`. In `backend/app/api/routes/items.py:10`, that router has prefix
   `/items` and tag `items`; its `@router.get("/", response_model=ItemsPublic)` at
   lines 13-15 therefore handles the full path.
3. FastAPI resolves `SessionDep` and `CurrentUser` in
   `backend/app/api/deps.py`. `SessionDep` calls `get_db` (lines 21-23), which
   yields a SQLModel `Session(engine)`. `CurrentUser` calls `get_current_user`
   (lines 30-46): it decodes the bearer JWT with `settings.SECRET_KEY` and
   `security.ALGORITHM`, validates `TokenPayload`, loads `User` by the token's
   `sub`, and rejects an invalid token, missing user, or inactive user.
4. FastAPI invokes `read_items` in `backend/app/api/routes/items.py:14-45`.
   `skip` defaults to 0 and `limit` to 100.
   
   - For a superuser (`current_user.is_superuser` true), lines 22-27 count all
     `Item` rows and select all items, ordered by `created_at` descending and
     paginated with offset/limit.
   - Otherwise, lines 29-42 count only rows where
     `Item.owner_id == current_user.id` and apply the same owner predicate,
     ordering, and pagination to the item query. Thus a non-superuser cannot see
     another user's items in this collection; the count is also owner-scoped.

5. Lines 44-45 convert each ORM `Item` to the allowlisted `ItemPublic` schema
   with `ItemPublic.model_validate`, then return `ItemsPublic(data=items_public,
   count=count)`. FastAPI serializes that response model. `ItemPublic` is defined
   in `backend/app/models.py:103-107`, so the response contains `id`, `title`,
   `description`, `owner_id`, and `created_at`, but not database-only fields.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` returns `f"{route.tags[0]}-{route.name}"`, and the
FastAPI app passes it as `generate_unique_id_function` at line 24. For the items
router this gives operation IDs such as `items-read_items`, which the generated
client exposes as readable methods such as `ItemsService.readItems` (see
`frontend/src/client/sdk.gen.ts`).

If the function were removed, FastAPI's default operation IDs would include the
route function, full API path, and HTTP method. For the items operations they
would be approximately:

| Route function | Default operation ID | Generated client method shape |
|---|---|---|
| `read_items` | `read_items_api_v1_items__get` | `readItemsApiV1ItemsGet` |
| `read_item` | `read_item_api_v1_items__id__get` | `readItemApiV1ItemsIdGet` |
| `create_item` | `create_item_api_v1_items__post` | `createItemApiV1ItemsPost` |
| `update_item` | `update_item_api_v1_items__id__put` | `updateItemApiV1ItemsIdPut` |
| `delete_item` | `delete_item_api_v1_items__id__delete` | `deleteItemApiV1ItemsIdDelete` |

The generator camel-cases the verbose operation IDs; the exact generated spelling
can vary with generator normalization of the slash-induced underscores, but the
important change is the loss of the short `readItems`/`readItem` names and the
addition of `ApiV1...Method` path/method text.

## 3. Removing `ondelete="CASCADE"`

The declaration is `backend/app/models.py:97-99`; the corresponding schema
migration is `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:22-26`,
which creates the `item.owner_id -> user.id` foreign key with `ondelete='CASCADE'`.
If the model change were accompanied by the necessary migration, direct database
deletion of a user while owned Items still exist would no longer cascade and could
fail with a foreign-key violation (or leave deletion behavior dependent on the
caller). The DB-level guarantee would be gone.

There is no existing test function that actually catches that specific regression.
`backend/tests/api/routes/test_users.py:test_delete_user_me` and
`test_delete_user_super_user` delete users but create no owned Item and do not
assert child-row deletion. Moreover, `User.items` still has
`cascade_delete=True` at `backend/app/models.py:59`, and `delete_user` explicitly
deletes Items first at `backend/app/api/routes/users.py:228-231`; those behaviors
would mask removal of the database-level cascade in the covered paths. A proper
regression test would create a user plus Item, delete the user, and assert the Item
is gone (and separately test a direct DB delete if the DB-level cascade is the
requirement).

## 4. `DUMMY_HASH`

In `backend/app/crud.py:45-60`, `authenticate` looks up the user first. If no
user exists, it still calls `verify_password(password, DUMMY_HASH)` at lines
47-50, then returns `None`. `DUMMY_HASH` is a fixed Argon2 hash (lines 40-42),
so the nonexistent-account path performs work comparable to checking a real
hash with a wrong password. Without it, response timing could reveal whether an
email address exists, enabling account/email enumeration. This is the timing
attack mitigation described in `docs/ard/0002-jwt-bearer-auth.md:26-29`.

## 5. Non-owner protection for `GET /items/{id}`

The mechanism is the inline application authorization check in
`backend/app/api/routes/items.py:48-58`, inside `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

Before that check, `session.get(Item, id)` returns the row or line 55 raises a
404. `CurrentUser` authentication comes from `backend/app/api/deps.py:30-49`,
but the owner restriction itself is this route-level predicate; it is not
PostgreSQL row-level security. The exact regression test for this endpoint is
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`,
which sends a non-owner token and asserts HTTP 403 plus the same detail.
