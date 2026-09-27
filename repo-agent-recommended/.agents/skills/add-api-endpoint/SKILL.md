---
name: add-api-endpoint
description: Add or modify a FastAPI route in this repo — which dependencies to use for auth/DB, the ownership-check convention sibling routes follow, and response-model rules. Also applies to changing an existing endpoint's parameters.
---

# Add or change an API endpoint

1. Add or edit the route function in the relevant file under `backend/app/api/routes/`
   (`items.py`, `users.py`, etc.) — one router per resource, already registered in
   `backend/app/api/main.py`.
2. Use the existing dependencies from `backend/app/api/deps.py`:
   `SessionDep` for a DB session, `CurrentUser` for the authenticated user (raises
   401/403 automatically), `get_current_active_superuser` as an extra dependency for
   admin-only routes.
3. Match the ownership-check pattern already used by sibling endpoints in the same
   file (e.g. `items.py`'s read/update/delete all check
   `current_user.is_superuser or item.owner_id == current_user.id`) rather than
   inventing a new authorization style.
4. Set `response_model` to a `*Public` schema, never the raw table model.
5. If you added a new route or changed a response/request schema, regenerate the
   frontend client (see the `regenerate-frontend-client` skill) so the change is
   actually callable from the UI. A new query parameter on an existing route with an
   unchanged response schema doesn't require this.
6. When you're done, see the `verify-work` skill before calling it complete.
