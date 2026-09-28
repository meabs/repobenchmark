---
name: run-tests
description: How to actually run this repo's test suite locally — the Postgres dependency, the settings module it uses, and what a clean run looks like. Use before claiming a change is verified.
---

# Run the test suite

1. Requires a running local Postgres reachable as `localhost:5432` under your
   OS user, with a database matching `DATABASE_NAME` (default `oscar`) — create
   it first if it doesn't exist: `createdb -h localhost oscar` (or set
   `DATABASE_NAME`/`DATABASE_USER`/`DATABASE_PASSWORD`/`DATABASE_HOST`/`DATABASE_PORT`
   env vars to point elsewhere — see `tests/settings.py`).
2. Install once: `python3 -m venv venv --upgrade-deps && venv/bin/pip install -e .[test]`.
3. Run: `venv/bin/py.test -q tests/`. `tests/conftest.py` sets
   `DJANGO_SETTINGS_MODULE=tests.settings` automatically — you don't need to
   export it yourself.
4. `tests/settings.py` is **not** the same app configuration as `sandbox/`: it
   forks 5 apps (`catalogue`, `customer`, `checkout`, `dashboard`, `partner`)
   to `tests._site.apps.*` specifically to exercise the override mechanism
   under test (see its comment: "Use a custom partner app to test overriding
   models"). If a change behaves differently under `tests.settings` vs.
   `sandbox.settings`, that's expected and usually means it interacts with
   one of those 5 forked apps — check `tests/_site/apps/<app>/` for what's
   actually overridden there.
5. A full clean run currently passes with 1 pre-existing skip unrelated to
   any specific change — a new failure or a new skip you introduced means
   something in your change broke, not the harness.
