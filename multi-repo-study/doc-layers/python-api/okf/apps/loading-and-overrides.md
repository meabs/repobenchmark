---
type: concept
title: Class loading and model overrides
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - src/oscar/core/loading.py
  - src/oscar/apps/catalogue/models.py
  - tests/settings.py
  - tests/_site/apps/catalogue/models.py
  - sandbox/settings.py
---

# Class loading and model overrides

## `get_class` / `get_classes`

`src/oscar/core/loading.py`'s `default_class_loader(module_label, classnames,
module_prefix)`:

1. Imports `oscar.apps.<module_label>` (the "core" version).
2. Finds which app is actually registered in `INSTALLED_APPS` for that app
   label (`_find_registered_app_name`). If it's not Oscar's own path, it also
   imports `<that_app's_dotted_path>.<rest_of_module_label>` (the "local"
   version).
3. For each requested class name, returns the **local** version if it
   exists, else the **core** version (`_pluck_classes`).

So `get_class("catalogue.forms", "ProductForm")` returns a project's own
`ProductForm` if the project forked `catalogue` and defined one, otherwise
Oscar's. Almost all cross-module references inside Oscar itself go through
this instead of `import`, so a fork is picked up everywhere automatically —
no need to hunt down every direct import site.

## Model overrides

`src/oscar/apps/catalogue/models.py` is the concrete-model half of this
pattern: it imports everything from `abstract_models.py` (`AbstractProduct`,
`AbstractCategory`, ...) and, for each one, does:

```python
if not is_model_registered("catalogue", "Product"):
    class Product(AbstractProduct):
        pass
```

`is_model_registered` (`loading.py`) checks Django's app registry for an
already-registered model with that name. A fork defines its own
`models.py` with the same pattern but a non-trivial subclass (extra fields),
and as long as its app is loaded into `INSTALLED_APPS` *before* the fields
are needed, Oscar's own `models.py` sees the model already registered and
skips defining its version — there is exactly one `Product` model at runtime,
either Oscar's or the fork's, never both.

## Where this is actually exercised in this repo

`sandbox/settings.py`'s `INSTALLED_APPS` uses vanilla
`"oscar.apps.catalogue.apps.CatalogueConfig"`-style entries for every app —
it does not fork anything. `tests/settings.py` is the one place with a live,
working fork: it swaps 5 apps to `tests._site.apps.*` equivalents
specifically to test that the override machinery works — see its comment
"Use a custom partner app to test overriding models." Read
`tests/_site/apps/catalogue/models.py` for the minimal-fork shape (in this
case it just re-exports Oscar's own classes unchanged, since the test only
needs the *loading path* to be exercised, not new fields).
