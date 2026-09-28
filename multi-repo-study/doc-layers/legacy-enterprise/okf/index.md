---
okf_version: "0.2"
---

# Spring Framework PetClinic — Knowledge Bundle

This is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/open-knowledge-format)
v0.2 bundle: plain markdown files with YAML frontmatter, cross-linked like a small
knowledge graph. Each concept file's `type` field says what kind of thing it
documents. Only this root `index.md` carries frontmatter beyond a concept doc's own
— and only the reserved `okf_version` key, per spec.

## Trust tier

Every concept doc in this bundle carries `generated: { by: reference_agent/claude-sonnet-5,
at: 2026-09-28 }` and a `sources` entry pointing at the real source file it
describes, but **no `verified` entry** — every doc here sits at OKF's `unverified`
trust tier: machine-written, cross-checked against the actual source at write time,
but not human-reviewed since. Treat claims in this bundle as a well-researched
starting point, not ground truth — cross-check anything consequential against the
`sources` file it names, especially the runtime-default-profile claim in
`repositories/index.md`, which is easy to get backwards (see that doc's own
warning).

## Contents

- [repositories/](repositories/index.md) — the 3 parallel repository
  implementations behind one set of interfaces, and which one is actually active at
  runtime by default (it's not the one you'd guess).
- [model/](model/index.md) — the domain entities (`Owner`, `Pet`, `Vet`, `Visit`,
  `PetType`) and how they're persisted differently depending on the active profile.
- [web/](web/index.md) — the controller/JSP layer and its conventions.
- [log.md](log.md) — notes on how this bundle was built.

For *how to make a given kind of change*, see `../AGENTS.md` and
`.agents/skills/`.
