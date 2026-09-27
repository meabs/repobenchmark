# Answers

## 1. `GET /api/v1/items/`

From the UI, `frontend/src/routes/_layout/items.tsx:getItemsQueryOptions` supplies
the React Query `queryFn`, which calls `ItemsService.readItems({ query: { skip: 0,
limit: 100 } })`. `frontend/src/client/sdk.gen.ts:ItemsService.readItems` makes
the generated-client GET request to `/api/v1/items/`, marks it as bearer-authenticated,
and returns the response data. `frontend/src/main.tsx` has configured the shared
client with `baseURL` and an `auth` callback reading `localStorage` key
`access_token`; `frontend/src/client/core/auth.gen.ts:getAuthToken` turns that
token into `Authorization: Bearer <token>`.

On the server, `backend/app/main.py` constructs the FastAPI app with
`generate_unique_id_function=custom_generate_unique_id` and includes
`api_router` under `settings.API_V1_STR` (`/api/v1`). `backend/app/api/main.py`
includes `items.router`. That router is declared in
`backend/app/api/routes/items.py` as `APIRouter(prefix="/items", tags=["items"])`,
and its `@router.get("/")` handler is `read_items`.

Before `read_items` runs, its `SessionDep` dependency invokes
`backend/app/api/deps.py:get_db`, which opens `Session(engine)` and yields it;
its `CurrentUser` dependency invokes `get_current_user`, which decodes the JWT
with `settings.SECRET_KEY`, validates `TokenPayload`, loads the subject with
`session.get(User, token_data.sub)`, and rejects an invalid token, missing user,
or inactive user. `read_items` then executes this branch:

- For a superuser (`current_user.is_superuser` true), it counts every `Item`
  (`select(func.count()).select_from(Item)`) and selects every Item, ordered by
  `created_at` descending, with `offset(skip)` and `limit(limit)`.
- For a non-superuser, it counts only rows where `Item.owner_id ==
  current_user.id`, and selects only those rows with the same descending
  `created_at` ordering and pagination.

Finally, `read_items` converts each result with `ItemPublic.model_validate(item)`
and returns `ItemsPublic(data=items_public, count=count)`. FastAPI serializes
that response according to `ItemsPublic` in `backend/app/models.py`.

## 2. `custom_generate_unique_id`

In `backend/app/main.py:14-15`, `custom_generate_unique_id(route)` returns
`f"{route.tags[0]}-{route.name}"`. For this endpoint, the tag is `items` and
the function name is `read_items`, so its OpenAPI operation ID is
`items-read_items`. That is why the generated client exposes
`ItemsService.readItems` (and types such as `itemsReadItemsData`).

If the custom function were removed, FastAPI's default generator would build an
ID from `route.name + route.path_format`, replace non-word characters with `_`,
and append the HTTP method. The relevant IDs would therefore be
`read_items_items__get` for `/items/` and `read_item_items__id__get` for
`/items/{id}`. The generated TypeScript operation methods would correspondingly
be names along the lines of `readItemsItemsGet` and `readItemItemsIdGet`, rather
than the concise `readItems` and `readItem` names currently present in
`frontend/src/client/sdk.gen.ts`.

## 3. Removing `Item.owner_id`'s `ondelete="CASCADE"`

`backend/app/models.py:97-99` currently makes the `item.owner_id -> user.id`
foreign key a database-level `ON DELETE CASCADE`. Removing it (and applying the
matching schema change) means a direct database deletion of a User who still has
Items will no longer delete those Items; PostgreSQL will reject the parent
delete with a foreign-key violation instead. The intended ORM-side behavior is
also represented by `User.items = Relationship(..., cascade_delete=True)` at
`backend/app/models.py:59`, while `backend/app/api/routes/users.py` explicitly
deletes owned Items in `delete_user` (lines 228-230). Thus those application
paths may still succeed, but the database-level cascade guarantee is gone.

The existing test function exercising the self-delete path is
`backend/tests/api/routes/test_users.py:test_delete_user_me`. However, it only
creates and checks a User, not an owned Item, so as currently written it would
not actually catch an orphan/foreign-key cascade regression. The superuser
delete test, `test_delete_user_super_user`, also does not test the FK cascade
because the route explicitly deletes the Items. A test that creates an Item for
the user and then verifies the Item is gone is absent from the current suite.

## 4. Why verify `DUMMY_HASH`

`backend/app/crud.py:authenticate` first looks up the email. When no user is
found, it still calls `verify_password(password, DUMMY_HASH)` and then returns
`None`. `verify_password` in `backend/app/core/security.py` delegates to
`PasswordHash.verify_and_update`, so this performs the same expensive Argon2
verification work as the real-user branch. Without it, an unknown email would
return much faster than a known email with a wrong password, allowing an
attacker to distinguish registered email addresses by response timing. The
dummy hash is a fixed Argon2 hash of a random password; its result is discarded.

## 5. Per-item ownership check

The exact mechanism is the conditional in
`backend/app/api/routes/items.py:56-57`, inside `read_item`:

```python
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
```

The handler first loads the row with `session.get(Item, id)` and raises 404 if it
does not exist. For an existing row, a non-superuser whose UUID differs from
`item.owner_id` receives 403; a matching owner, or any superuser, reaches
`return item`. The regression/behavior test is
`backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions`.
