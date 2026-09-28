---
okf_version: "0.2"
---

# bulletproof-react (react-vite app) — Knowledge Bundle

This is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/open-knowledge-format)
v0.2 bundle: plain markdown files with YAML frontmatter, cross-linked like a small
knowledge graph. Each concept file's `type` field says what kind of thing it
documents. Only this root `index.md` carries frontmatter beyond a concept doc's own
— and only the reserved `okf_version` key, per spec.

## Trust tier

Every concept doc in this bundle carries `generated: { by: reference_agent/claude-sonnet-5,
at: ... }` and a `sources` entry pointing at the real source file it describes, but
**no `verified` entry** — meaning every doc here sits at OKF's `unverified` trust
tier: machine-written, not yet human-reviewed. Treat claims in this bundle as a
well-researched starting point, not ground truth — cross-check anything
consequential against the `sources` file it names.

## Contents

- [architecture/](architecture/index.md) — the feature-folder layout and shared UI
  component conventions.
- [backend-mock/](backend-mock/index.md) — how the entirely-mocked backend (MSW +
  in-memory db) works, since there is no real API server in this repo.
- [testing/](testing/index.md) — the test setup, including the env-var requirement
  that breaks every test file if skipped.
- [routing/](routing/index.md) — how routes, paths, and auth-gating fit together.
- [log.md](log.md) — chronological notes on this bundle and things discovered while
  building it.

For *how to make a given kind of change*, see `.agents/skills/` (via `../AGENTS.md`).
