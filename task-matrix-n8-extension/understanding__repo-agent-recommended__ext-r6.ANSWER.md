# Answers

## 1. `GET /api/v1/items/`

1. The frontend route `frontend/src/routes/_layout/items.tsx`, in `getItemsQueryOptions`, calls `ItemsService.readItems({ query: { skip: 0, limit: 100 } })` (lines 12–17).
2. `frontend/src/client/sdk.gen.ts`, `ItemsService.readItems` (lines 287–300), sends an authenticated `GET` to `/api/v1/items/`; the generated client marks the operation as bearer-authenticated.
3. `backend/app/main.py` creates the FastAPI app and includes `api_router` with `settings.API_V1_STR` as prefix (lines 21–25 and 35). Thus the route prefix is `/api/v1`.
4. `backend/app/api/main.py` adds `items.router` to `api_router` (line 10).
5. `backend/app/api/routes/items.py` defines `router = APIRouter(prefix="/items", tags=["items"])` (line 10) and `read_items` for `GET /` (lines 13–16), producing the full path `/api/v1/items/`.
6. FastAPI resolves the injected `SessionDep` and `CurrentUser` parameters. `SessionDep` is `Annotated[Session, Depends(get_db)]` in `backend/app/api/deps.py` (lines 21–27); `get_db` opens `Session(engine)` from `backend/app/core/db.py` and yields it (lines 7 and 21–23). `CurrentUser` is `Annotated[User, Depends(get_current_user)]` (line 49).
7. `get_current_user` in `backend/app/api/deps.py` (lines 30–46) decodes the bearer JWT with `jwt.decode` using `settings.SECRET_KEY` and `security.ALGORITHM`, validates `TokenPayload`, loads the user with `session.get(User, token_data.sub)`, and rejects an invalid token (403), missing user (404), or inactive user (400). It returns the active `User`.
8. `read_items` then branches on `current_user.is_superuser` (backend/app/api/routes/items.py, lines 21–42):
   - Superuser: counts all `Item` rows (`select(func.count()).select_from(Item)`, lines 22–23), then selects all Items ordered by `created_at` descending, applies `skip` and `limit` (lines 24–27).
   - Non-superuser: counts only rows where `Item.owner_id == current_user.id` (lines 29–34), then selects only those same owned rows, with the same descending `created_at`, offset, and limit (lines 35–42).
9. The selected ORM objects are converted with `ItemPublic.model_validate` and returned as `ItemsPublic(data=items_public, count=count)` (lines 44–45). `ItemPublic` exposes `id`, `owner_id`, `created_at`, `title`, and `description` in `backend/app/models.py` (lines 103–107), while `ItemsPublic` contains `data` and `count` (lines 110–113). FastAPI applies the declared `response_model=ItemsPublic`.

## 2. `custom_generate_unique_id`

`backend/app/main.py:14-15` defines `custom_generate_unique_id(route: APIRoute) -> str` as `f"{route.tags[0]}-{route.name}"`. For this route, the tag is `items` and the Python function name is `read_items`, so the OpenAPI operation ID is `items-read_items`. The FastAPI app installs it via `generate_unique_id_function=custom_generate_unique_id` at lines 21–25.

The generated client configuration in `frontend/openapi-ts.config.ts:11-18` groups operations by tag, names the container `{{name}}Service`, and strips the tag-plus-hyphen prefix. That is why the current generated method is `ItemsService.readItems` in `frontend/src/client/sdk.gen.ts:293`.

If the custom generator were removed and the client were regenerated with the same config, FastAPI's default operation ID for this route would be `read_items_items__get` (function name + normalized path + HTTP method). The generated method would therefore be named `ItemsService.readItemsItemsGet` (with the analogous path/method suffixes on the other item operations), rather than `readItems`.

## 3. Removing `ondelete="CASCADE"` from `Item.owner_id`

`backend/app/models.py:97-100` maps `Item.owner_id` to the `user.id` foreign key and currently declares `ondelete="CASCADE"`. Removing it means the database foreign key would no longer delete an owner's Item rows automatically when the User row is deleted. A direct database-level User deletion would instead be rejected by the foreign-key constraint (or, if constraints were changed separately, could leave orphaned Items).

There is an important codebase-specific qualification: the currently applied Alembic migration `backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py:20-27` creates the database foreign key with `ondelete='CASCADE'`, and the application deletion paths already remove children: `delete_user_me` in `backend/app/api/routes/users.py:132-143` relies on the SQLModel relationship's `cascade_delete=True` (`models.py:59`), while `delete_user` explicitly executes `delete(Item).where(col(Item.owner_id) == user_id)` at `users.py:228-230`.

No existing test function actually catches removal of the database `ondelete` behavior: `test_delete_user_me` and `test_delete_user_super_user` in `backend/tests/api/routes/test_users.py` do not create or assert deletion of an Item, and `test_delete_user_super_user` uses the explicit Item delete in the route. Thus the exact answer is: there is no such existing test. A regression test would need to create an Item for the deleted User and assert that it is gone after User deletion.

## 4. `DUMMY_HASH` in `crud.authenticate`

`backend/app/crud.py:45-60` first looks up the email with `get_user_by_email`. If no user exists, lines 47–51 call `verify_password(password, DUMMY_HASH)` and return `None`. `DUMMY_HASH` (lines 40–42) is a fixed Argon2 hash of a random password. The verification is intentionally performed even though its result is discarded: Argon2's expensive work makes the nonexistent-user path take approximately the same time as the existing-user path, reducing email/user-enumeration timing attacks. If a user exists, the function instead verifies against `db_user.hashed_password` and returns the user only when verification succeeds.

## 5. Non-owner protection for `GET /items/{id}`

The exact mechanism is the guard in `backend/app/api/routes/items.py:53-58`, inside `read_item`: it loads the row with `session.get(Item, id)`, returns 404 if absent, then evaluates `if not current_user.is_superuser and (item.owner_id != current_user.id):` and raises `HTTPException(status_code=403, detail="Not enough permissions")`.

The existing test `backend/tests/api/routes/test_items.py:test_read_item_not_enough_permissions` (lines 55–65) exercises this pattern by creating an Item owned by a different random user, requesting it with `normal_user_token_headers`, and asserting HTTP 403 plus the same detail.
