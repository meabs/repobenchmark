---
type: Topology
title: Compose service topology
description: Services, ports, and dependencies defined in compose.yml.
resource: compose.yml
tags: [docker, deployment]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: compose
    resource: compose.yml
    title: Source file this concept describes
stale_after: 2027-03-25
---

# Compose service topology

```
                    ┌──────────────┐
   :80 ────────────▶│    proxy     │  Traefik — only service with a host port
                    │ (traefik)    │  routes by Docker labels, nothing exposed
                    └──────┬───────┘  by default
                           │
           ┌───────────────┼───────────────┐
           ▼               ▼               ▼
   backend-http    adminer-http     (any future labeled service)
   Host(${DOMAIN})  Host(adminer.${DOMAIN})
           │               │
           ▼               ▼
   ┌──────────────┐  ┌──────────┐
   │   backend    │  │ adminer  │
   │  (FastAPI +  │  │ (DB UI)  │
   │  built SPA)  │  └────┬─────┘
   └──────┬───────┘       │
          │ depends_on:   │
          │ service_healthy
          ▼               ▼
   ┌─────────────────────────┐
   │           db             │
   │      (postgres:18)       │
   └─────────────────────────┘
```

- Only `proxy` has a host-mapped port; every other service is reached through it.
- `backend` won't be routed to until its own healthcheck
  (`GET /api/v1/utils/health-check/`, see [routers/utils](../routers/utils.md)) passes,
  and it won't even start until `db`'s healthcheck (`pg_isready`) passes.
- In production, `backend` also serves the built frontend — there is no separate
  frontend container (see [services/frontend](../services/frontend.md)).
- `compose.override.yml` adds dev-only settings (e.g. bind mounts for hot reload) on
  top of this; `compose.deploy.yml` adds production-only settings. Same base graph
  either way.

See [ARD 0003](../../docs/ard/0003-docker-compose-traefik-topology.md) for the reasoning.
