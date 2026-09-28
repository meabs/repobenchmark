---
okf_version: "0.2"
---

# Spring PetClinic — Knowledge Bundle

This is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/open-knowledge-format)
v0.2 bundle: plain markdown files with YAML frontmatter, cross-linked like a small
knowledge graph. Each concept file's `type` field says what kind of thing it
documents. Only this root `index.md` carries frontmatter beyond a concept doc's own
— and only the reserved `okf_version` key, per spec.

## Trust tier

Every concept doc in this bundle carries `generated: { by: reference_agent/claude-sonnet-5,
at: 2026-09-28T09:39:22Z }` and a `sources` entry pointing at the real source file it
describes, but **no `verified` entry** — meaning every doc here sits at OKF's
`unverified` trust tier: machine-written, not yet human-reviewed. Treat claims in
this bundle as a well-researched starting point, not ground truth — cross-check
anything consequential against the `sources` file it names.

## Contents

- [domain/](domain/index.md) — the JPA entities (`Owner`, `Pet`, `Vet`, `Visit`,
  `PetType`) and how they relate.
- [web/](web/index.md) — the controller layer: routing, form-binding/mass-assignment
  protection, and the pagination convention shared across list pages.
- [testing/](testing/index.md) — the test-profile setup: default H2 tests vs. the
  Docker-gated MySQL/Postgres integration tests, and why 2 tests normally skip.
- [log.md](log.md) — chronological notes on this bundle and things discovered while
  building it.

For *how to make a given kind of change* in this codebase, see the skills under
`../.agents/skills/`.
