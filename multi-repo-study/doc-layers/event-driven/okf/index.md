---
okf_version: "0.2"
---

# eShop — Ordering Subsystem Knowledge Bundle

This is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/open-knowledge-format)
v0.2 bundle: plain markdown files with YAML frontmatter, cross-linked like a small
knowledge graph. Each concept file's `type` field says what kind of thing it
documents. Only this root `index.md` carries frontmatter beyond a concept doc's own
— and only the reserved `okf_version` key, per spec.

**Scope**: this bundle documents only the Ordering subsystem
(`src/Ordering.Domain/`, `src/Ordering.Infrastructure/`, `src/Ordering.API/`) of the
full eShop reference app. Catalog, Basket, Identity, Webhooks, and the Aspire
AppHost are real, working parts of this repo but are not covered here.

## Trust tier

Every concept doc in this bundle carries `generated: { by: reference_agent/claude-sonnet-5,
at: ... }` and a `sources` entry pointing at the real source file it describes, but
**no `verified` entry** — every doc here sits at OKF's `unverified` trust tier:
machine-written, not yet human-reviewed. Treat claims as a well-researched starting
point, not ground truth — cross-check anything consequential against the `sources`
file it names, especially anything about failure/exception behavior. See `log.md`
for what was actually checked against source while building this bundle, including
one place where a first-drafted claim turned out to need a correction after
re-reading the code.

## Contents

- [domain/](domain/index.md) — the Order/Buyer aggregates, their invariants, and the
  Domain vs. Application vs. API layering.
- [application/](application/index.md) — the CQRS command flow, the idempotency
  wrapper, and the pipeline behaviors (logging/transaction/validation).
- [events/](events/index.md) — domain events vs. integration events, and how one
  becomes the other.
- [log.md](log.md) — chronological notes on this bundle and things discovered while
  building it.

For *how to make a given kind of change*, see `../.agents/skills/`. For a quick
orientation and the test command, see `../AGENTS.md`.
