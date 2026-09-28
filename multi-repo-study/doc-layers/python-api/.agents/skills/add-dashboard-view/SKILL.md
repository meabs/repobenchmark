---
name: add-dashboard-view
description: Add a new view/page to the merchant-facing dashboard (under a dashboard sub-app like dashboard/reports, dashboard/catalogue, etc). Covers Oscar's apps.py-based URL and permission registration, which does NOT use a normal Django urls.py.
---

# Add a dashboard view

Dashboard sub-apps (`src/oscar/apps/dashboard/<name>/`) register URLs and
permissions on their `OscarDashboardConfig` subclass in `apps.py`, not in a
`urls.py` — e.g. `dashboard/reports/apps.py`'s `ReportsDashboardConfig`:

1. Write the view (typically in that sub-app's `views.py`), loaded elsewhere
   via `get_class` rather than a direct import — follow how the existing
   `IndexView` in the same sub-app is defined and referenced.
2. In the sub-app's `apps.py`, load your view in `ready()` with
   `self.my_view = get_class("dashboard.<name>.views", "MyView")`, then add a
   `path(...)` for it inside `get_urls()`, returned through
   `self.post_process_urls(urls)` (don't return the raw list — see how
   `ReportsDashboardConfig.get_urls` does it).
3. Give the new URL a permission entry in `configure_permissions()`'s
   `self.permissions_map`, keyed by the URL's `name` — either a plain
   permission string (see `default_permissions`) or a
   `DashboardPermission.get(app_label, codename)` call. An unregistered URL
   name is reachable but unprotected — don't skip this.
4. Add the page's template under
   `src/oscar/templates/oscar/dashboard/<name>/` extending
   `oscar/dashboard/layout.html`, matching sibling templates in the same
   directory.
5. Add a test under the matching `tests/` subtree that GETs the new URL as a
   staff user and asserts a 200 plus the expected content, and asserts a
   non-staff user is denied.
