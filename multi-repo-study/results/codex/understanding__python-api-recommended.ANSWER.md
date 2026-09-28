# Answers

## 1. Class loading and app ownership

`get_class("catalogue.forms", "ProductForm")` in `src/oscar/core/loading.py:25-40` is a one-class wrapper: it calls `get_classes(...)` and returns element zero. The call chain is:

1. `get_classes` (`loading.py:48-50`) calls the configured loader.
2. `get_class_loader` (`loading.py:43-45`) imports the callable named by `settings.OSCAR_DYNAMIC_CLASS_LOADER` (normally `default_class_loader`).
3. `default_class_loader` (`loading.py:53-132`) first imports Oscar's module, `oscar.apps.catalogue.forms`, via `_import_module` (`loading.py:135-159`). It then calls `_find_registered_app_name("catalogue.forms")`.
4. `_find_registered_app_name` (`loading.py:183-199`) takes the first label component, `catalogue`, and performs the exact registry lookup `apps.get_app_config(app_label)`. A `LookupError` becomes `AppNotFoundError`; the result must also satisfy `isinstance(app_config, OscarConfig)`, otherwise it raises `AppNotFoundError`. It returns `app_config.name`, the dotted package path of the registered app.
5. If that name starts with `oscar.` (more exactly, `module_prefix + "."`), no local import is attempted. Otherwise, `default_class_loader` builds `<app_config.name>.forms` and imports it with `_import_module`.
6. `_pluck_classes([local_module, oscar_module], ["ProductForm"])` (`loading.py:161-180`) checks the local module first and returns its attribute when present; otherwise it returns Oscar's attribute. Thus a fork that defines `ProductForm` wins, while a fork without that class falls back to `oscar.apps.catalogue.forms.ProductForm`.

`_import_module` returns `None` only for a missing module import (and re-raises an import error originating inside an otherwise-found module). `_pluck_classes` raises `ClassNotFoundError` if neither module has the requested class.

## 2. `is_model_registered` and duplicate concrete models

`is_model_registered` (`src/oscar/core/loading.py:270-280`) does exactly this:

```python
try:
    apps.get_registered_model(app_label, model_name)
except LookupError:
    return False
else:
    return True
```

It checks Django's already-registered model registry by `(app_label, model_name)`; it does not inspect a model's Python module or determine which class is the preferred fork.

For the guarded Oscar pattern in `src/oscar/apps/catalogue/models.py:37-42`, the first concrete model registered under `("catalogue", "Product")` wins. When the second app's `models.py` evaluates the guard, `get_registered_model` succeeds, so its `class Product(AbstractProduct): pass` statement is skipped. There is therefore one registered `Product`, selected by app/model-loading order, rather than two.

If both class declarations bypassed that guard and attempted to register the same registry key, Django's app registry would raise its conflicting-model `RuntimeError`. If the models use different app labels, Django treats them as different models; two AppConfigs with the same app label are rejected earlier as duplicate application labels. Oscar's supported fork arrangement replaces the corresponding Oscar app in `INSTALLED_APPS` instead of installing both versions.

## 3. Forks in `sandbox/`

No. `sandbox/settings.py:258-297` uses Oscar's own `oscar.apps.<app>.apps.<Config>` entries, including `oscar.apps.catalogue.apps.CatalogueConfig`; it does not put a project fork in `INSTALLED_APPS`.

The live fork list elsewhere is `tests/settings.py:72-83`. It replaces exactly five entries with these fork configs:

- `partner` → `tests._site.apps.partner.apps.PartnerConfig`
- `customer` → `tests._site.apps.customer.apps.CustomerConfig`
- `catalogue` → `tests._site.apps.catalogue.apps.CatalogueConfig`
- `dashboard` → `tests._site.apps.dashboard.apps.DashboardConfig`
- `checkout` → `tests._site.apps.checkout.apps.CheckoutConfig`

## 4. `AbstractCondition.type` versus `proxy_class`

`type` (`src/oscar/apps/offer/abstract_models.py:829-854`) is the built-in condition selector. Its `TYPE_CHOICES` are `Count`, `Value`, and `Coverage`; `proxy_map` (`lines 867-873`) maps those values to `CountCondition`, `ValueCondition`, and `CoverageCondition`, loaded through `get_class("offer.conditions", ...)`.

`proxy_class` (`line 859`) is a database field holding a dotted Python class path for a custom condition. `BaseOfferMixin.proxy` (`abstract_models.py:37-61`) gives `proxy_class` priority: it calls `load_proxy(self.proxy_class)` and constructs that class. Only when `proxy_class` is empty does it use `self.type` in `proxy_map`.

A plain `class MyCondition(AbstractCondition): ...` does **not** make the offer engine use that class. The offer stores an `offer.Condition` row, and `ConditionalOffer.is_condition_satisfied` (`abstract_models.py:355-356`) calls `self.condition.proxy().is_satisfied(...)`; `proxy()` does not discover arbitrary Python subclasses. With no `proxy_class`, it selects only the built-in class for `type` (or raises the unrecognised-type `RuntimeError` if no mapped type exists). A custom condition must be registered as the explicit proxy class path—Oscar's `offer.custom.create_condition` (`custom.py:39-43`) writes that path—and normally is a proxy subclass of the concrete `Condition` model, as in `tests/_site/model_tests_app/models.py:58-66`.

## 5. Test database defaults

`tests/settings.py:11-20` defaults to:

- engine: `django.db.backends.postgresql`
- database name: `oscar`
- user: `None`
- password: `None`
- host: `""` (empty string)
- port: `5432`

The database name is overridden with the environment variable `DATABASE_NAME`. The same settings block also permits `DATABASE_ENGINE`, `DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_HOST`, and `DATABASE_PORT`; additionally, `tests/conftest.py:29-31` sets SQLite and `:memory:` when pytest is run with `--sqlite`.
