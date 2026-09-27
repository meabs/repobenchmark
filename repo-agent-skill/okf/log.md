# Directory Update Log

## 2026-09-25

* **Creation**: This bundle is a copy of the OKF v0.2 knowledge graph originally
  built for a sibling repo (`repo-agent-optimised`) in the same `benchmark` repo
  pair (see [`../SETUP.md`](/../SETUP.md)) — same source
  (`fastapi/full-stack-fastapi-template` @ `cb740b656d7a0a6c5e12c7bf8e50343ec94ee9c7`),
  same "what things are and how they relate" content. This repo pairs it with
  [`SKILL.md`](/SKILL.md) (how to do the work) instead of that sibling's
  `AGENTS.md` + `docs/ard/` (why things are built the way they are) — an ablation
  to test which kind of guidance actually moves the needle on task completion.
  Cross-references to `docs/ard/*` that existed in the source bundle were removed
  or redirected to `SKILL.md` where the topic was actually procedural (e.g.
  writing a migration, regenerating the frontend client).

* **Known history worth knowing**: an earlier version of the sibling repo's
  `AGENTS.md` flagged `backend/app/api/deps.py`'s
  `except InvalidTokenError, ValidationError:` as an upstream Python syntax bug.
  It wasn't — the check ran on the wrong Python version; this project pins Python
  ≥3.14, and [PEP 758](https://peps.python.org/pep-0758/) makes that exact syntax
  valid (parsed as `except (A, B):`). An agent trusted the doc and made an
  unnecessary "fix" as a result. Nothing in this bundle references that claim
  (it was never carried over), but if you're auditing `deps.py` for any reason,
  know that this line is intentional, not broken.
