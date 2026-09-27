# Directory Update Log

## 2026-09-25

* **Update**: Bundle upgraded to [OKF v0.2](https://github.com/GoogleCloudPlatform/open-knowledge-format).
  Removed frontmatter from every `index.md` and from this file (v0.2: reserved
  filenames carry no frontmatter, except `okf_version` at the bundle root — see
  [index.md](index.md)). Added trust-signal fields to all 11 concept docs:
  `generated: { by, at }` and a `sources` entry pointing at the real source file
  each doc describes. Deliberately did **not** add a `verified` entry anywhere —
  none of this bundle has had human sign-off, and claiming otherwise would defeat
  the point of the signal. See [index.md](index.md)'s "Trust tier" section.

## 2026-09-24

* **Correction**: The entry below (same day) was wrong. The `ast.parse` check that
  flagged `backend/app/api/deps.py`'s `except InvalidTokenError, ValidationError:`
  as broken syntax ran on the system's Python 3.13, not the interpreter this project
  targets. `backend/pyproject.toml` pins `requires-python = ">=3.14,<4.0"`, and
  Python 3.14 shipped [PEP 758](https://peps.python.org/pep-0758/), which makes that
  exact bare-comma form valid — parsed as `except (A, B):`. Verified directly:
  `uv run --python 3.14 python3 -c "import ast; print(ast.dump(ast.parse('try:\n pass\nexcept A, B:\n pass').body[0].handlers[0].type))"`
  prints `Tuple(elts=[Name(id='A', ...), Name(id='B', ...)], ...)`. Nothing in that
  file needed patching. This came to light because an agent working from this
  repo's docs "fixed" the non-bug based on the entry below, while an agent working
  from raw source in a sibling repo (no such doc) correctly left the file alone —
  see [`AGENTS.md`](/AGENTS.md)'s "Python version note". Moral: an agent-facing doc
  that states a fact incorrectly can cost more effort than no doc at all.

* **Creation**: Bundle created for the `benchmark` repo pair (see
  [`../SETUP.md`](/../SETUP.md)) — this repo is the "agent-optimised" half of a
  two-repo comparison, cloned from `fastapi/full-stack-fastapi-template` @
  `cb740b656d7a0a6c5e12c7bf8e50343ec94ee9c7`. While writing these docs, flagged
  `backend/app/api/deps.py` line 36 as a genuine upstream Python syntax bug and
  recorded it in `AGENTS.md` — corrected above.
