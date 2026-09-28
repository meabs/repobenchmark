# Answers

## 1. Dynamic class loading and `ProductForm`

`get_class("catalogue.forms", "ProductForm")` follows this call chain:

1. `get_class` in `src/oscar/core/loading.py:25-40` calls `get_classes` with a one-element class-name list.
2. `get_classes` (`:48-50`) calls the cached `get_class_loader` (`:43-45`). That function resolves `settings.OSCAR_DYNAMIC_CLASS_LOADER` with Django's `import_string`; the default in `src/oscar/defaults.py:9` is `oscar.core.loading.default_class_loader`.
3. `default_class_loader` (`src/oscar/core/loading.py:53-132`) imports Oscar's candidate, `oscar.apps.catalogue.forms`, via `_import_module` (`:135-159`). It then calls `_find_registered_app_name("catalogue.forms")` (`:183-199`).
4. `_find_registered_app_name` takes `app_label = module_label.split(".")[0]` (`"catalogue"`), then performs the registry lookup `apps.get_app_config(app_label)`. A missing label raises `AppNotFoundError`; crucially, the returned config must pass the exact ownership check `isinstance(app_config, OscarConfig)`, or it raises `AppNotFoundError` as well. If it passes, the function returns `app_config.name`.
5. If that name starts with `oscar.apps.`, `default_class_loader` treats the registered app as Oscar's own and does not import a second local module (`local_module = None`, lines `112-116`). Otherwise it constructs the local module label by joining the registered app name with the suffix of the requested label (`lines 117-120`). For example, a registered `tests._site.apps.catalogue` app yields `tests._site.apps.catalogue.forms`.
6. `_pluck_classes` (`:161-180`) receives `[local_module, oscar_module]` and, for each requested class, returns the first module having that attribute. Therefore a project module's `ProductForm` wins; if it has no `ProductForm`, Oscar's `oscar.apps.catalogue.forms.ProductForm` is used. If neither module imports, `default_class_loader` raises `ModuleNotFoundError`; if neither contains the class, `_pluck_classes` raises `ClassNotFoundError`.

The registry check is not a scan for arbitrary Python modules: it is `apps.get_app_config("catalogue")` followed by `isinstance(app_config, OscarConfig)`. The config's `.name` is what selects the package from which the local candidate is imported.

## 2. `is_model_registered` and duplicate `Product` models

`is_model_registered` is `src/oscar/core/loading.py:270-280`:

```python
try:
    apps.get_registered_model(app_label, model_name)
except LookupError:
    return False
else:
    return True
```

It checks only whether Django's app registry already contains the exact `(app_label, model_name)` pair. It does not inspect `INSTALLED_APPS`, compare subclasses, or import a model module. In `src/oscar/apps/catalogue/models.py:37-42`, Oscar defines `Product(AbstractProduct)` only when the registry does not already contain `catalogue.Product`; this lets a fork that registered that model first prevent Oscar's concrete model from being created.

For the relevant collision—two concrete models both registered as `catalogue.Product`—this is not a last-one-wins mechanism. The first model is registered; when Django's app registry tries to register the second different model under the same app label and model name, Django raises a `RuntimeError` for conflicting models in application `catalogue` during app population. If the two apps use different app labels, their `Product` models are different registry keys and can coexist, but neither is an override of `catalogue.Product`.

## 3. App forks in the sandbox versus the live test project

No: `sandbox/settings.py:258-309` lists the original Oscar configs, including `oscar.apps.checkout.apps.CheckoutConfig`, `oscar.apps.catalogue.apps.CatalogueConfig`, `oscar.apps.partner.apps.PartnerConfig`, `oscar.apps.customer.apps.CustomerConfig`, and `oscar.apps.dashboard.apps.DashboardConfig`. It does not replace any of them with `sandbox.*` or another project app. The local modules under `sandbox/apps/` are not evidence of an installed Oscar fork because they are not used as replacements in that `INSTALLED_APPS` list.

The live fork list elsewhere is `tests/settings.py:22-83` (selected by `tests/conftest.py:13-14`). It replaces exactly five Oscar entries by index:

- partner: `tests._site.apps.partner.apps.PartnerConfig` (`tests/settings.py:74-75`)
- customer: `tests._site.apps.customer.apps.CustomerConfig` (`:76-77`)
- catalogue: `tests._site.apps.catalogue.apps.CatalogueConfig` (`:78-79`)
- dashboard: `tests._site.apps.dashboard.apps.DashboardConfig` (`:80-81`)
- checkout: `tests._site.apps.checkout.apps.CheckoutConfig` (`:82-83`)

Thus the repo's live `INSTALLED_APPS` fork count is **5**.

## 4. `AbstractCondition.type`, `proxy_class`, and custom conditions

In `src/oscar/apps/offer/abstract_models.py`:

- `AbstractCondition.TYPE_CHOICES` (`:829-846`) defines Oscar's built-in condition kinds: `Count`, `Value`, and `Coverage`. The `type` `CharField` (`:854`) stores one of those values. `proxy_map` (`:867-873`) maps those values to `CountCondition`, `ValueCondition`, and `CoverageCondition`.
- `proxy_class` is a separate nullable string field (`:859`) containing a dotted Python class path for a custom condition. `oscar.apps.offer.custom.create_condition` (`src/oscar/apps/offer/custom.py:39-43`) persists that path in a `Condition` record.

`BaseOfferMixin.proxy` (`abstract_models.py:37-61`) checks `proxy_class` first and loads/instantiates that class through `load_proxy` (`:51-56`). Only when `proxy_class` is empty does it use `type` as a key in `proxy_map` (`:57-58`); an unknown or empty type then raises the `RuntimeError` at `:59-61`. The offer engine calls `self.condition.proxy().is_satisfied(self, basket)` in `AbstractConditionalOffer.is_condition_satisfied` (`:355-356`), not `self.condition.is_satisfied(...)` directly.

Therefore, `class MyCondition(AbstractCondition): ...` as a plain Django subclass will **not** make Oscar use `MyCondition.is_satisfied` merely because the class exists. A plain subclass is a separate concrete model unless it is explicitly made a proxy of the concrete `offer.Condition`, and Oscar's `Condition` foreign key/proxy dispatch does not discover arbitrary subclasses. The stored condition will instead dispatch by its `proxy_class` or by its `type`; with neither set, `proxy()` raises the runtime error above. The working pattern is a proxy subclass of concrete `Condition` plus a condition record whose `proxy_class` stores its dotted path, as demonstrated by `tests/_site/model_tests_app/models.py:22-30` and `tests/integration/offer/test_condition.py:318-330`.

## 5. Test database defaults

`tests/conftest.py:13-14` selects `tests.settings` for pytest. In `tests/settings.py:11-20`, the default database connection is:

- engine: `django.db.backends.postgresql` (unless `DATABASE_ENGINE` is set)
- name: `oscar` (unless `DATABASE_NAME` is set)
- user: `None` (unless `DATABASE_USER` is set)
- password: `None` (unless `DATABASE_PASSWORD` is set)
- host: `""` (unless `DATABASE_HOST` is set)
- port: `5432` (unless `DATABASE_PORT` is set)

The specific environment variable for pointing the suite at a different database name is **`DATABASE_NAME`**. The `--sqlite` pytest option in `tests/conftest.py:29-31` is a separate convenience that sets both `DATABASE_ENGINE` to SQLite and `DATABASE_NAME` to `:memory:`.
