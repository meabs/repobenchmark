---
type: Service
title: Frontend
description: React + TypeScript SPA, file-based routing, generated API client.
resource: frontend/src/main.tsx
tags: [typescript, react, spa]
generated: { by: reference_agent/claude-sonnet-5, at: 2026-09-25T00:00:00Z }
sources:
  - id: main
    resource: frontend/src/main.tsx
    title: Source file this concept describes
stale_after: 2027-03-25
---

# Frontend

React 19 + TypeScript SPA, built with Vite. Entry: `frontend/src/main.tsx`.

## Stack

- **Routing**: [TanStack Router](https://tanstack.com/router), file-based — files
  under `frontend/src/routes/` become routes; `frontend/src/routeTree.gen.ts` is
  generated from them, do not hand-edit.
- **Server state**: TanStack Query (`@tanstack/react-query`).
- **UI components**: Radix UI primitives + `class-variance-authority`/`clsx`
  (shadcn/ui style), under `frontend/src/components/`.
- **API client**: `frontend/src/client/` — generated from the backend's OpenAPI schema,
  never hand-edited. See
  [ARD 0005 — generated TypeScript client](../../docs/ard/0005-generated-typescript-client.md).
- **Tests**: Playwright (`bun run test`).

## Routes (`frontend/src/routes/`)

| File | Path |
|---|---|
| `login.tsx` | `/login` |
| `signup.tsx` | `/signup` |
| `recover-password.tsx` | `/recover-password` |
| `reset-password.tsx` | `/reset-password` |
| `_layout.tsx` + `_layout/index.tsx` | `/` (authenticated shell) |
| `_layout/items.tsx` | `/items` |
| `_layout/admin.tsx` | `/admin` |
| `_layout/settings.tsx` | `/settings` |

## Build

`bun run build` runs `tsc -p tsconfig.build.json && vite build`. In production, the
built output is served by the [backend](backend.md), not by a separate frontend
container — see
[deployment/topology](../deployment/topology.md).
