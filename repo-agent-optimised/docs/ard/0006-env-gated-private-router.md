# 0006. `private` router is only mounted when `FASTAPI_ENV=development`

## Status
Accepted (`backend/app/api/main.py`, `backend/app/api/routes/private.py`)

## Context
Local development and e2e tests need a fast way to create users without going through
the real signup/email flow. Adding an authenticated-admin-only endpoint for this would
still require bootstrapping a superuser first, and adding it to the normal auth-required
surface risks it being mistaken for (or reused as) a real feature.

## Decision
`backend/app/api/routes/private.py` defines `POST /api/v1/private/users/`, which creates
a user directly from `{email, password, full_name, is_verified}` with **no
authentication dependency at all** — deliberately, since it exists purely for local
seeding/testing convenience. `backend/app/api/main.py` only calls
`api_router.include_router(private.router)` inside
`if settings.FASTAPI_ENV == "development":` — so in any environment where
`FASTAPI_ENV` isn't explicitly set to `"development"` (see `Settings.FASTAPI_ENV`'s
type: `Literal["development"] | None`), the route doesn't exist on the running app at
all, not merely "hidden."

## Consequences
- This is a real, unauthenticated user-creation endpoint. Its safety depends entirely
  on `FASTAPI_ENV` never being set to `"development"` in a reachable deployment —
  `compose.yml`'s `backend` service does not set `FASTAPI_ENV`, so it defaults to
  `None` and the router is excluded there. Anyone changing how `FASTAPI_ENV` is set
  (e.g. adding it to a shared `.env` that also gets used in a deployed environment)
  should treat this as a security-relevant change, not just a dev-convenience toggle.
- When reading `docs/api/openapi.json`, remember it was exported with
  `FASTAPI_ENV=development` (see `scripts/generate-client.sh` and
  `docs/ard/0005-generated-typescript-client.md`), so it includes `/private/users/` —
  that path will not exist on a production deployment's actual `/openapi.json`.
