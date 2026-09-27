# 0003. Docker Compose + Traefik for deployment topology

## Status
Accepted (`compose.yml`, `compose.override.yml`, `compose.deploy.yml`)

## Context
The stack has four independently-deployable pieces (reverse proxy, DB, DB admin UI,
backend API — the frontend is served as static files by the backend in production, see
`backend/app/main.py`'s `app.frontend("/", directory=FRONTEND_DIR)`) that need routing,
TLS termination, and service discovery without a full orchestrator like Kubernetes.

## Decision
`compose.yml` defines the base topology, routed through Traefik rather than exposing
container ports directly:

- **`proxy`** (Traefik v3.7): the only service with a host-mapped port. Reads Docker
  labels (`traefik.http.routers.*`) on other services to build its routing table —
  services opt in per-container (`traefik.enable=true`), nothing is exposed by default
  (`--providers.docker.exposedbydefault=false`).
- **`db`** (Postgres 18): has a healthcheck (`pg_isready`); `backend` depends on it with
  `condition: service_healthy`, so the API container won't start accepting traffic
  before the DB is actually ready, not just started.
- **`adminer`**: DB admin UI, routed by Traefik at `adminer.${DOMAIN}`.
- **`backend`**: routed by Traefik at `${DOMAIN}` itself (root domain serves the API —
  and, in the production image, the built frontend static files too). Has its own
  healthcheck hitting `/api/v1/utils/health-check/`.

`compose.override.yml` layers local-dev conveniences on top (see that file);
`compose.deploy.yml` layers production-specific settings (no source bind-mounts, uses
pre-built images) on top of the same base.

## Consequences
- Adding a new backend-adjacent service means adding Traefik labels, not manually
  wiring ports/nginx config.
- `DOMAIN` and `POSTGRES_PASSWORD` etc. are required env vars (`:?Variable not set`
  syntax) — compose refuses to start with defaults in a real deploy, forcing them to be
  set explicitly.
