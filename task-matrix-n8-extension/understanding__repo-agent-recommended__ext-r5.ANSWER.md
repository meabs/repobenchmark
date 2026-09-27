# Answers

## 1. `GET /api/v1/items/`

The backend path is assembled and dispatched in this order:

1. `backend/app/main.py`: `app = FastAPI(...)` is created and `app.include_router(api_router, prefix=settings.API_V1_STR)` mounts the API under `/api/v1`. `backend/app/api/main.py` has already put `items.router` into `api_router` with `api_router.include_router(items.router)`.
2. `backend/app/api/routes/items.py`: `router = APIRouter(prefix="/items", tags=["items"])` and `@router.get("/")` register `read_items`, producing `/api/v1/items/`.
3. FastAPI resolves `SessionDep` and `CurrentUser` in `read_items`'s parameters. `SessionDep` is `Annotated[Session, Depends(get_db)]` in `backend/app/api/deps.py`; `get_db()` opens `Session(engine)` using `backend/app/core/db.py`'s `engine` and yields it. `CurrentUser` is `Annotated[User, Depends(get_current_user)]`; `get_current_user()` in `backend/app/api/deps.py` decodes the bearer JWT with `security.ALGORITHM`, validates `TokenPayload`, loads `User` with `session.get(User, token_data.sub)`, and rejects an invalid token (403), missing user (404), or inactive user (400).
4. `backend/app/api/routes/items.py:14`, `read_items(session, current_user, skip=0, limit=100)`, branches on `current_user.is_superuser`.
5. For a superuser, it runs `select(func.count()).select_from(Item)` for the unfiltered total, then selects every `Item`, ordered by `col(Item.created_at).desc()`, with `.offset(skip).limit(limit)`. For a non-superuser, both the count query and item query add `.where(Item.owner_id == current_user.id)`; the item query has the same descending `created_at`, offset, and limit. Thus a superuser receives all items and the global count; a non-superuser receives only owned items and that user's count. `skip`/`limit` apply to the returned rows, not to the count.
6. The function converts each row with `ItemPublic.model_validate(item)` and returns `ItemsPublic(data=items_public, count=count)` from `backend/app/models.py`. FastAPI applies the declared `response_model=ItemsPublic` and serializes the response.

On the frontend, `frontend/src/routes/_layout/items.tsx`'s query function calls `ItemsService.readItems({ query: { skip: 0, limit: 100 } })`; `frontend/src/client/sdk.gen.ts:293` sends the authenticated GET to `/api/v1/items/` through the generated client.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines `custom_generate_unique_id(route: APIRoute) -> str` as `f"{route.tags[0]}-{route.name}"`. `FastAPI(..., generate_unique_id_function=custom_generate_unique_id)` therefore gives the items routes operation IDs such as `items-read_items`, `items-create_item`, `items-read_item`, `items-update_item`, and `items-delete_item` (visible in `docs/api/openapi.json`).

`frontend/openapi-ts.config.ts:11-18` groups operations by tags into `ItemsService`, then removes the prefix through `name.replace(/^[^-]*-/, "")` before converting the remaining snake_case name to the generated method spelling. That is why the current methods are `ItemsService.readItems`, `createItem`, `readItem`, `updateItem`, and `deleteItem` in `frontend/src/client/sdk.gen.ts`.

If the custom generator were removed, FastAPI's default `generate_unique_id` would use `route.name + route.path_format`, replace non-word characters with `_`, and append the HTTP method. The item operation IDs would consequently be:

- `read_items_api_v1_items__get` → `ItemsService.readItemsApiV1ItemsGet`
- `create_item_api_v1_items__post` → `ItemsService.createItemApiV1ItemsPost`
- `read_item_api_v1_items__id__get` → `ItemsService.readItemApiV1ItemsIdGet`
- `update_item_api_v1_items__id__put` → `ItemsService.updateItemApiV1ItemsIdPut`
- `delete_item_api_v1_items__id__delete` → `ItemsService.deleteItemApiV1ItemsIdDelete`

The long suffixes arise because the default IDs include the full `/api/v1` path; the tag grouping would still put them in `ItemsService`.

## 3. Removing `ondelete="CASCADE"`

`backend/app/models.py:97-99` declares `Item.owner_id` as a non-nullable foreign key to `user.id` with database-level `ondelete="CASCADE"`. Removing it (and applying the corresponding schema change) removes the database safeguard that deletes dependent Items when their User is deleted; a direct database/user deletion that leaves dependent rows would instead be rejected by the foreign-key constraint.

For this repository's current HTTP paths, there are two additional protections: `User.items = Relationship(..., cascade_delete=True)` at `models.py:59` gives the ORM delete cascade for `delete_user_me`, while `backend/app/api/routes/users.py:228-230`, in `delete_user`, explicitly executes `delete(Item).where(col(Item.owner_id) == user_id)` before deleting the user. Removing the model option alone also does not alter an already-applied database constraint; the existing Alembic migration `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:25-26` is what created the current DB-level cascade.

The existing user-deletion test intended to cover this area is `backend/tests/api/routes/test_users.py::test_delete_user_me`, but it creates and deletes a user with no Item and only asserts that the User is gone. Therefore, strictly speaking, no existing test actually catches loss of the Item cascade; `test_delete_user_me` would need to create an owned Item and assert that it is gone. `test_delete_user_super_user` likewise creates no Item and exercises the explicit-delete route.

## 4. `DUMMY_HASH`

`backend/app/crud.py:45-60`, `authenticate`, first looks up the email with `get_user_by_email`. If no user exists, it still calls `verify_password(password, DUMMY_HASH)` and returns `None`. `DUMMY_HASH` is a fixed Argon2 hash of a random password, and `verify_password` in `backend/app/core/security.py:29-32` performs the expensive password-hash verification.

That equalizes the work and approximate response time for an unknown email and a known email with a wrong password. Without the dummy verification, attackers could use timing differences to enumerate which email addresses exist.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the application-level guard in `backend/app/api/routes/items.py:53-57`, inside `read_item`:

```python
item = session.get(Item, id)
if not item:
    raise HTTPException(status_code=404, detail="Item not found")
if not current_user.is_superuser and (item.owner_id != current_user.id):
    raise HTTPException(status_code=403, detail="Not enough permissions")
return item
```

`current_user` is supplied by the `CurrentUser` dependency, so a non-superuser whose ID differs from `item.owner_id` gets 403 before the Item is returned. The corresponding regression test is `backend/tests/api/routes/test_items.py::test_read_item_not_enough_permissions`.
