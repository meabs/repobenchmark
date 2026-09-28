---
name: override-app
description: Fork/override an Oscar app (e.g. to customize a model or view) the way a downstream project would — which files to create, how INSTALLED_APPS must point at the fork instead of the Oscar original, and how the class/model loader picks the fork over the core app.
---

# Override (fork) an Oscar app

Oscar apps are not meant to be edited in place under `src/oscar/apps/` for
project-specific customization — they're meant to be **forked**: a local app
with the same `app_label` that either extends Oscar's abstract base classes
or reuses Oscar's views/forms wholesale.

1. Create a local Django app whose models module mirrors the pattern in
   `src/oscar/apps/<app>/models.py`: import everything from
   `oscar.apps.<app>.abstract_models`, then define the concrete classes
   yourself (e.g. `class Product(AbstractProduct): new_field = ...`), guarded
   by `oscar.core.loading.is_model_registered("<app_label>", "<ModelName>")`
   exactly as the real `models.py` does — copy that file as your starting
   point, don't write the guard from scratch.
2. For views/forms/other non-model classes you're not touching, either don't
   define them in the fork at all (they're transparently loaded from Oscar —
   see `okf/index.md`'s section on `get_class`/`get_classes`), or define only
   the ones you're changing.
3. In `INSTALLED_APPS` (in the settings module you're wiring, e.g. a
   `sandbox`-style project settings file), replace the Oscar entry — e.g.
   `"oscar.apps.catalogue.apps.CatalogueConfig"` — with your fork's dotted
   path, e.g. `"myproject.apps.catalogue.apps.CatalogueConfig"`. This repo's
   own `tests/settings.py` does exactly this for 5 apps (catalogue, customer,
   checkout, dashboard, partner) — read it and `tests/_site/apps/` as a real,
   working example before writing your own; **`sandbox/` does NOT fork
   anything** — its `INSTALLED_APPS` (in `sandbox/settings.py`) uses the
   vanilla `oscar.apps.*.apps.*Config` entries throughout, so don't copy it as
   an override example.
4. Write a migration for any new/changed model field inside your fork app,
   not inside `src/oscar/apps/`.
5. Run the `run-tests` skill's checklist to confirm the fork resolves
   correctly (`get_class`/`get_model` must find your local class, not
   Oscar's).
