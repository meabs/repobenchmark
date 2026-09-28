# AGENTS.md

django-oscar: a Django e-commerce framework, not a single app. Every Oscar app
ships as an *overridable* Django app (see `okf/index.md`) and this repo is the
framework package itself, plus a `sandbox/` reference project and a `tests/`
suite that exercises it. Read this file first — it only points, it doesn't
explain.

- **What things mean, and why they're built that way where it matters** (the
  fork/override mechanism, key apps and their abstract-model pattern, the
  sandbox project, how the test suite is wired — rationale is folded into the
  relevant doc, not a separate tree): [`okf/index.md`](okf/index.md).
- **How to do a specific kind of change**: `.agents/skills/` has one skill per
  task, each with its own scope — open the one(s) whose description matches
  what you're about to do, not all of them:
  - `override-app` — fork/override an Oscar app's model or view in a project
  - `add-model-field` — add a field to an existing Oscar model + migration
  - `add-offer-condition-or-benefit` — add a new promotions Condition/Benefit
  - `add-dashboard-view` — add a new view/page to the merchant dashboard
  - `run-tests` — how to actually run the suite and what it needs (Postgres)
- **Human setup/running instructions**: `README.rst`, `CONTRIBUTING.rst`,
  `sandbox/README.rst` — not duplicated here.

Nothing else lives in this file. If you find yourself adding an explanation or
a procedure here, it belongs in `okf/` or one of the skills instead.
