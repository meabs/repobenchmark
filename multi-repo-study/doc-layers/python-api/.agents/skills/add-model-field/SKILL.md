---
name: add-model-field
description: Add a field to an existing Oscar model (e.g. Product, Category, Order) and write the accompanying migration. Covers where the field goes (abstract vs. concrete class) and how to generate a migration that lands in the right app.
---

# Add a field to an Oscar model

1. Find the model's **abstract** definition — e.g. `Product` lives as
   `AbstractProduct` in `src/oscar/apps/catalogue/abstract_models.py`; the
   concrete `Product` in `src/oscar/apps/catalogue/models.py` is just
   `class Product(AbstractProduct): pass` behind an
   `is_model_registered(...)` guard. Add the new field to the **abstract**
   class, not the concrete one — that's the pattern every existing field in
   this codebase follows, and it's what makes the field available to a
   project that forks the app (see the `override-app` skill).
2. Migrations for core apps live under
   `src/oscar/apps/<app_label>/migrations/`, numbered sequentially (check the
   highest existing number, e.g. `0032_...` in `catalogue`, and continue from
   there). Generate one with Django's `makemigrations` against a settings
   module that has the app installed unforked — `sandbox/settings.py`'s
   `INSTALLED_APPS` uses the vanilla `oscar.apps.<app>.apps.<App>Config`
   entries for every app except none (it forks nothing), so it's the
   reference project to generate against:
   `DJANGO_SETTINGS_MODULE=sandbox.settings python sandbox/manage.py makemigrations <app_label>`.
   Verify the generated file actually lands in
   `src/oscar/apps/<app_label>/migrations/` before trusting it.
3. Apply and verify against a real database, not just eyeballing the
   generated file — see the `run-tests` skill for how to get a working
   Postgres connection, then run the migration and check it applies cleanly.
4. Add or update a test in the matching `tests/` subtree
   (`tests/integration/<app>/` or `tests/unit/<app>/`, whichever mirrors
   where the model's other tests already live) that exercises the new field.
