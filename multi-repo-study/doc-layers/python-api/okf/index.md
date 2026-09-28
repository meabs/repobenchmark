---
okf_version: "0.2"
---

# django-oscar — Knowledge Bundle

This is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/open-knowledge-format)
v0.2 bundle: plain markdown files with YAML frontmatter, cross-linked like a
small knowledge graph. Each concept file's `type` field says what kind of
thing it documents. Only this root `index.md` carries frontmatter beyond a
concept doc's own — and only the reserved `okf_version` key, per spec.

## Trust tier

Every concept doc in this bundle carries `generated: { by: reference_agent/claude-sonnet-5,
at: 2026-09-28 }` and a `sources` entry pointing at the real source file it
describes, but **no `verified` entry** — meaning every doc here sits at OKF's
`unverified` trust tier: machine-written, not yet human-reviewed. Treat claims
in this bundle as a well-researched starting point, not ground truth —
cross-check anything consequential against the `sources` file it names.

## The core idea: Oscar is forked, not configured

Oscar is a Django e-commerce **framework**, distributed as a set of Django
apps under `src/oscar/apps/<name>/` (catalogue, basket, checkout, offer,
order, dashboard, ...). A project using Oscar is expected to **fork** the
apps it needs to customize, rather than set config flags. Two mechanisms make
this work:

1. **Class loading** (`src/oscar/core/loading.py`): `get_class`/`get_classes`
   look up a class by `(module_label, classname)` against whichever app is
   registered in Django's `INSTALLED_APPS` for that label. If a local fork
   defines the class, it wins; otherwise it falls back to Oscar's own
   version. Nearly every cross-app reference in Oscar goes through this
   instead of a plain `import`, which is what makes forking transparent.
2. **Model overriding**: each app's `abstract_models.py` defines
   `Abstract<Name>` classes; `models.py` instantiates the concrete version —
   `class Product(AbstractProduct): pass` — guarded by
   `is_model_registered(app_label, model_name)` so a fork's own concrete
   class (with extra fields) is used instead, and Oscar's own never gets
   registered twice.

See [`apps/loading-and-overrides.md`](apps/loading-and-overrides.md) for the
full mechanism with source citations.

**Important**: `sandbox/` (this repo's reference Django project) does **not**
demonstrate forking — its `INSTALLED_APPS` uses vanilla
`oscar.apps.<app>.apps.<App>Config` entries throughout. The only place in
this repo that actually forks apps in a live `INSTALLED_APPS` is
`tests/settings.py`, which forks 5 apps specifically to test the override
mechanism. See [`testing/test-suite.md`](testing/test-suite.md).

## Contents

- [apps/index.md](apps/index.md) — the app-fork/override mechanism, and a
  survey of the major apps (catalogue, offer, dashboard).
- [testing/index.md](testing/index.md) — how the test suite is organized,
  what it needs to run, and how `tests.settings` differs from `sandbox`.
- [deployment/index.md](deployment/index.md) — the sandbox reference project
  and how it's normally run.
- [log.md](log.md) — chronological notes on this bundle and things
  discovered while building it.

For *how to make a given kind of change* in this codebase, see
`../AGENTS.md` and `.agents/skills/`.
