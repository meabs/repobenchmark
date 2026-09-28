---
type: log
title: Bundle log
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
---

# Log

- 2026-09-28: Bundle created against `python-api-baseline` @ commit `d9d2b3f`
  (upstream django-oscar `0ae2005bad81254db837101e1977526ebe29cc1e`, with
  `src/oscar/locale` and `docs/images` stripped as irrelevant bulk). Grounded
  in direct reads of `src/oscar/core/loading.py`,
  `src/oscar/apps/catalogue/{abstract_models,models}.py`,
  `src/oscar/apps/offer/abstract_models.py`, `src/oscar/apps/dashboard/*/apps.py`,
  `sandbox/settings.py`, `tests/settings.py`, and `tests/_site/apps/catalogue/models.py`.
- The one deliberately-flagged fact worth double-checking if anything here
  seems off: **`sandbox/` does not fork any Oscar apps** — this is stated
  confidently in three places in this bundle (`index.md`,
  `apps/loading-and-overrides.md`, `testing/test-suite.md`) because it was
  verified directly by reading `sandbox/settings.py`'s `INSTALLED_APPS` list
  end-to-end, not inferred from the directory name or README.
