---
type: concept
title: Test suite
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - tests/settings.py
  - tests/conftest.py
  - tests/_site/apps
  - setup.cfg
---

# Test suite

Run via `venv/bin/py.test -q tests/` (pytest, configured by `[tool:pytest]`
in `setup.cfg`: `testpaths = tests/`). `tests/conftest.py` sets
`os.environ.setdefault("DJANGO_SETTINGS_MODULE", "tests.settings")`, so
Django is already configured correctly without exporting anything yourself.

`tests/settings.py` needs a real Postgres database (`DATABASES.default`,
defaulting to a DB named `oscar` on `localhost:5432` with no
user/password — i.e. peer/trust auth — overridable via `DATABASE_*` env
vars). There is no SQLite fallback in this settings module.

`tests/settings.py` is a **forked** app configuration, not a copy of
`sandbox/settings.py`: it takes the same `INSTALLED_APPS` list `sandbox`
would use, then explicitly swaps 5 entries —
`catalogue`, `customer`, `checkout`, `dashboard`, `partner` — for
`tests._site.apps.<name>.apps.<Name>Config` equivalents, with the comment
"Use a custom partner app to test overriding models. I can't find a way of
doing this on a per-test basis, so I'm using a global change." This is the
one place in this repo where the override mechanism
([loading-and-overrides.md](../apps/loading-and-overrides.md)) is live and
exercised — `sandbox/` itself forks nothing. If you're testing something
override-related, look at `tests/_site/apps/<name>/` first.

A full run currently passes with exactly 1 skip unrelated to any specific
change (verified against upstream commit
`0ae2005bad81254db837101e1977526ebe29cc1e`) — treat any additional skip or
failure your change introduces as a real regression, not test flakiness.
