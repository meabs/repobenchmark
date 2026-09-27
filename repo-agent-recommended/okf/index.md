---
okf_version: "0.2"
---

# Full Stack FastAPI Template — Knowledge Bundle

This is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/open-knowledge-format)
v0.2 bundle: plain markdown files with YAML frontmatter, cross-linked like a small
knowledge graph. Each concept file's `type` field says what kind of thing it documents.
Only this root `index.md` carries frontmatter beyond a concept doc's own — and only
the reserved `okf_version` key, per spec.

## Trust tier

Every concept doc in this bundle carries `generated: { by: reference_agent/claude-sonnet-5,
at: ... }` and a `sources` entry pointing at the real source file it describes, but
**no `verified` entry** — meaning every doc here sits at OKF's `unverified` trust
tier: machine-written, not yet human-reviewed. Treat claims in this bundle as a
well-researched starting point, not ground truth — cross-check anything
consequential against the `sources` file it names. This isn't hypothetical caution:
a sibling copy of this codebase once shipped an entry-point doc that flagged
`backend/app/api/deps.py` as having a syntax bug, checked against the wrong Python
version — it wasn't a bug. An agent that trusted the doc without checking made an
unnecessary code change as a result (see `log.md`).

## Contents

- [services/](services/index.md) — the running pieces (backend, frontend, db) and how they talk to each other.
- [tables/](tables/index.md) — database tables (`User`, `Item`).
- [routers/](routers/index.md) — API routers and their endpoints.
- [deployment/](deployment/index.md) — how it's deployed (Docker Compose + Traefik).
- [log.md](log.md) — chronological notes on this bundle and things discovered while building it.

For *how to make a given kind of change* in this codebase, see `../SKILL.md`. For the
exact API contract, see `../docs/api/openapi.json`.
