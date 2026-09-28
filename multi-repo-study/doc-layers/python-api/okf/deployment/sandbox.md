---
type: concept
title: Sandbox reference project
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - sandbox/settings.py
  - sandbox/manage.py
  - sandbox/urls.py
  - Makefile
---

# Sandbox reference project

`sandbox/` is a standalone Django project (its own `manage.py`, `settings.py`,
`urls.py`) that wires up Oscar's apps as a working storefront + dashboard for
local development, demos, and building the docs/screenshots — not a template
to fork from for override examples (see
[loading-and-overrides.md](../apps/loading-and-overrides.md) — `sandbox`'s
`INSTALLED_APPS` uses every Oscar app unmodified).

The `Makefile`'s `sandbox` target (`install build_sandbox`) installs
requirements, runs `npm install && npm run build` for static assets, then
resets and loads sandbox fixture data (`sandbox_clean` → `sandbox_load_user`
→ `sandbox_load_data`). This asset/fixture pipeline is separate from, and not
required by, the `tests/` suite — see
[../testing/test-suite.md](../testing/test-suite.md).
