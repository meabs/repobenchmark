---
type: concept
title: Dashboard app
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - src/oscar/apps/dashboard/apps.py
  - src/oscar/apps/dashboard/reports/apps.py
---

# Dashboard app

The merchant-facing back-office (`dashboard`, plus sub-apps like
`dashboard/reports`, `dashboard/catalogue`, `dashboard/orders`, ...). Each
sub-app's `OscarDashboardConfig` subclass (in its `apps.py`) registers its
own URLs and permissions in `ready()`/`get_urls()`/`configure_permissions()`
— there is no per-app `urls.py` the way a typical Django app has. See
`add-dashboard-view` in `.agents/skills/` for the concrete steps and the
`ReportsDashboardConfig` example it's based on.

The root `dashboard` app (`DashboardConfig` in `dashboard/apps.py`) also
wires up references to every sub-app's `AppConfig` instance
(`self.catalogue_app`, `self.reports_app`, ...) in its own `ready()`, which
is how cross-sub-app navigation/menu code (`dashboard/menu.py`,
`dashboard/nav.py`) finds them.
