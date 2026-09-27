# Benchmark task prompts

Three task types now, each run once against each repo in a **fresh agent session**
(no shared context between runs, no repo sees another's session, no repo sees
another task's session):

- **Task A — Understanding** (`## Task A`): no code change at all. Answers a fixed
  set of comprehension questions to a file. Isolates comprehension value with zero
  implementation noise.
- **Task B — Simple change** (`## Task B`): one small, single-concern backend
  change. Isolates orientation cost from implementation cost — small enough that
  getting oriented should dominate the session.
- **Task C — Complex change** (`## Task C`): the archive/soft-delete feature used in
  runs 1–4 — multi-file, backend + frontend + migration + e2e. Unchanged from
  before, kept as the upper end of the difficulty range.

Four repos now:

| Repo | Doc layer | Tests |
|---|---|---|
| `repo-baseline` | none | plain codebase |
| `repo-agent-optimised` | `AGENTS.md` + `docs/ard/` (why) + OKF v0.2 (what/relations) + static OpenAPI schema | entry point + rationale + knowledge graph |
| `repo-agent-skill` | tiny `AGENTS.md` skills index (pointers only) + 6 task-scoped skills under `.agents/skills/` (how) + OKF v0.2 (what/relations) + static OpenAPI schema | gradual disclosure: discover + trigger the relevant skill(s), knowledge graph, no rationale |
| `repo-agent-recommended` | tiny `AGENTS.md` skills index + the same 6 task-scoped skills + OKF v0.2 **with the load-bearing "why" facts folded directly into the relevant concept doc** (no separate `docs/ard/`) | our own synthesis of everything this study found so far — see below |

`repo-agent-skill` is an ablation: same declarative OKF layer as
`repo-agent-optimised`, but paired with procedural "how to do the work" skills
instead of an entry-point doc + architecture-decision rationale. It isolates whether
*how-to* guidance moves outcomes differently than *why* guidance, holding the
knowledge-graph layer constant. See `SETUP.md` for full provenance of all three.

**Gradual disclosure, tested for real:** as of the v3 restructure, none of
`repo-agent-skill`'s three task prompts below mention `AGENTS.md`, the skills, or
`okf/` at all — they're word-for-word identical to `repo-baseline`'s prompts (plus
`repo-baseline`'s own "work through this yourself" line). The single monolithic
`SKILL.md` was also split into 6 narrow, single-purpose skills (`model-field-change`,
`write-migration`, `add-api-endpoint`, `regenerate-frontend-client`,
`add-ui-action`, `verify-work`), each independently discoverable and each scoped
tightly enough that a given task should only need some of them, not all six. This
tests actual emergent discovery and relevance-matching — does the agent notice
`AGENTS.md` unprompted, and does it open the skill(s) whose description matches the
task at hand — rather than the agent being told exactly where to look, which is what
every prior version of this repo's prompts did. Caveat: `codex exec` has no
Claude-Code-style runtime skill-listing/auto-invocation mechanism — there's no
system-level "here are your available skills" injection. What's being measured here
is filesystem-level self-directed discovery (does the agent find and read the right
file), not model-level skill routing.

**`repo-agent-recommended`** applies that same discovery test but changes the doc
design itself, synthesizing what the study found up to this point:
- `AGENTS.md`, the skills, and the no-prompt-hints treatment are identical to
  `repo-agent-skill` v3 (nothing there was implicated in the one real cost effect
  this study found).
- `docs/ard/` is gone entirely. Auditing all 6 of `repo-agent-optimised`'s ARDs
  against OKF found 4 of 6 already fully duplicated in OKF's concept docs (cascade
  delete, env-gated private router, generated client, Alembic-over-create_all), and
  the remaining 2 facts that mattered (the `DUMMY_HASH` timing-attack mitigation,
  `custom_generate_unique_id`'s short-name rationale) weren't in OKF yet -- both
  were the kind of fact whose absence could cause a real regression (an agent
  "cleaning up" `authenticate()` by removing what looks like dead code). Those two
  got added as short notes inside the OKF concept doc they're actually attached to
  (`okf/routers/login.md`, `okf/services/backend.md`) instead of recreating a
  parallel "why" tree.
- Net effect under test: does dropping the always-loaded `docs/ard/` layer (the
  thing `repo-agent-optimised` paid a real per-session token cost for) while
  keeping the specific facts that were load-bearing reduce cost without losing
  correctness or comprehension quality?

**Before launching any of these:** start the session in your agent tool's
non-interactive / auto-approved mode (e.g. Codex's full-auto/danger-full-access
profile), not the default interactive one. Recommendation from reviewing runs 1–3:
wall-clock duration has been contaminated at least once by time spent idle between
human tool-approval prompts, which isn't part of what this benchmark is trying to
measure. If your tool has no such mode, don't trust that run's `duration_seconds` —
flag it in analysis instead, as was done for run 2.

Each prompt includes an identical metrics protocol at the end so runs can be compared
afterward. See the note at the bottom of this file for how to interpret
`RUN_METRICS.json`, and for independent post-run verification steps.

---

# Task C — Complex change (archive/soft-delete)

## Prompt: `repo-baseline`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: add "archive" (soft-delete) support for Items.

Requirements:
1. Add an `is_archived: bool` field to the Item table, default `false`, with a proper
   Alembic migration (don't rely on auto-create-all).
2. Add `POST /api/v1/items/{id}/archive` — sets `is_archived = true`. Same ownership
   rules as the existing item endpoints (owner or superuser only).
3. Add `POST /api/v1/items/{id}/unarchive` — sets it back to `false`. Same auth rules.
4. `GET /api/v1/items/` should exclude archived items by default, but accept an
   `include_archived: bool = false` query param to include them.
5. Regenerate the frontend's API client so it reflects the new endpoints/field.
6. In the frontend Items UI, add a way to archive/unarchive an item and visually
   distinguish archived items, following the existing UI patterns in that screen.

Definition of done — and how to check each one, not just assert it:
- Migration applies cleanly: actually run `alembic upgrade head` against a real,
  migrated-from-scratch database. Don't infer this from the generated file looking
  right.
- New endpoints respect the same ownership/superuser rules as the other item routes.
- Default item listing excludes archived items; `include_archived=true` includes them.
- Frontend client and UI reflect the change (no hand-edited generated client files).
- Existing tests still pass; add backend tests for the new behavior.
- **The UI actually works, not just compiles**: if this repo has Playwright specs
  under `frontend/tests/`, run them, or at minimum add/extend a spec that clicks the
  new archive/unarchive control and asserts the item's visual state changes. A
  passing backend test suite does not verify the button you added does anything —
  confirm the end-to-end behavior a real user would see, not just that the code
  compiles and unit tests are green.

Work through this yourself — explore the codebase as needed to find the relevant
files and match its existing conventions.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline: each time you finish a distinct phase
   (e.g. "explored repo", "read Item model", "wrote migration", "added archive
   endpoint", "added unarchive endpoint", "updated list endpoint", "regenerated
   frontend client", "updated UI", "ran backend tests", "ran e2e/Playwright check"),
   append one line to that timeline with a timestamp (`date -u +%FT%TZ`) and a short
   label. If any gap between two consecutive timeline events exceeds 5 minutes,
   record what you were doing/waiting on during that gap — don't let it pass silently.
3. Keep a running tally of tool calls by type as you go (file reads, file edits/writes,
   bash commands, searches/greps) — don't reconstruct this from memory at the end,
   increment it as you actually use each tool.
4. Also note: the timestamp of your *first* file edit/write (as distinct from
   read/explore actions) — this is "time to first edit," a proxy for how long
   orientation took before you started producing the change.
5. When the task is complete (or if you give up / hit a blocker you can't resolve),
   run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-baseline",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": [...],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "definition_of_done": {"<each checklist item as a short key>": true/false, "e2e_ui_behavior_verified": true/false},
  "docs_consulted": [],
  "blockers_hit": ["one line per blocker, e.g. bugs you had to work around, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "anything relevant to how easy or hard orientation was in this repo"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there)
   before your final commit, so it stays untracked and doesn't appear in the feature
   diff.
```

---

## Prompt: `repo-agent-optimised`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

This repo has an agent-oriented documentation layer on top of the application code.
Start by reading AGENTS.md at the repo root — it's the entry point and links to:
- docs/ard/ (Architecture Decision Records — why things are built the way they are)
- docs/api/openapi.json (the real, current API schema)
- okf/ (Open Knowledge Format docs — what each service, DB table, and router does,
  cross-linked)
Use these as your primary source of truth for how the codebase is structured before
reading raw source, and follow the conventions they document.

Task: add "archive" (soft-delete) support for Items.

Requirements:
1. Add an `is_archived: bool` field to the Item table, default `false`, with a proper
   Alembic migration (don't rely on auto-create-all).
2. Add `POST /api/v1/items/{id}/archive` — sets `is_archived = true`. Same ownership
   rules as the existing item endpoints (owner or superuser only).
3. Add `POST /api/v1/items/{id}/unarchive` — sets it back to `false`. Same auth rules.
4. `GET /api/v1/items/` should exclude archived items by default, but accept an
   `include_archived: bool = false` query param to include them.
5. Regenerate the frontend's API client so it reflects the new endpoints/field.
6. In the frontend Items UI, add a way to archive/unarchive an item and visually
   distinguish archived items, following the existing UI patterns in that screen.

Definition of done — and how to check each one, not just assert it:
- Migration applies cleanly: actually run `alembic upgrade head` against a real,
  migrated-from-scratch database. Don't infer this from the generated file looking
  right.
- New endpoints respect the same ownership/superuser rules as the other item routes.
- Default item listing excludes archived items; `include_archived=true` includes them.
- Frontend client and UI reflect the change (no hand-edited generated client files).
- Existing tests still pass; add backend tests for the new behavior.
- **The UI actually works, not just compiles**: if this repo has Playwright specs
  under `frontend/tests/`, run them, or at minimum add/extend a spec that clicks the
  new archive/unarchive control and asserts the item's visual state changes. A
  passing backend test suite does not verify the button you added does anything —
  confirm the end-to-end behavior a real user would see, not just that the code
  compiles and unit tests are green.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline: each time you finish a distinct phase
   (e.g. "read AGENTS.md", "read relevant ARD/OKF docs", "read Item model", "wrote
   migration", "added archive endpoint", "added unarchive endpoint", "updated list
   endpoint", "regenerated frontend client", "updated UI", "ran backend tests", "ran
   e2e/Playwright check"), append one line to that timeline with a timestamp
   (`date -u +%FT%TZ`) and a short label. If any gap between two consecutive
   timeline events exceeds 5 minutes, record what you were doing/waiting on during
   that gap — don't let it pass silently.
3. Keep a running tally of tool calls by type as you go (file reads, file edits/writes,
   bash commands, searches/greps) — don't reconstruct this from memory at the end,
   increment it as you actually use each tool.
4. Also note: the timestamp of your *first* file edit/write (as distinct from
   read/explore actions) — this is "time to first edit," a proxy for how long
   orientation took before you started producing the change.
5. When the task is complete (or if you give up / hit a blocker you can't resolve),
   run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-optimised",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": [...],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "definition_of_done": {"<each checklist item as a short key>": true/false, "e2e_ui_behavior_verified": true/false},
  "docs_consulted": ["which of AGENTS.md / docs/ard/* / docs/api/openapi.json / okf/* you actually opened, and roughly how you used each"],
  "blockers_hit": ["one line per blocker, e.g. bugs you had to work around, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "anything relevant to how much the docs did or didn't help"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there)
   before your final commit, so it stays untracked and doesn't appear in the feature
   diff.
```

---

## Prompt: `repo-agent-skill`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: add "archive" (soft-delete) support for Items.

Requirements:
1. Add an `is_archived: bool` field to the Item table, default `false`, with a proper
   Alembic migration (don't rely on auto-create-all).
2. Add `POST /api/v1/items/{id}/archive` — sets `is_archived = true`. Same ownership
   rules as the existing item endpoints (owner or superuser only).
3. Add `POST /api/v1/items/{id}/unarchive` — sets it back to `false`. Same auth rules.
4. `GET /api/v1/items/` should exclude archived items by default, but accept an
   `include_archived: bool = false` query param to include them.
5. Regenerate the frontend's API client so it reflects the new endpoints/field.
6. In the frontend Items UI, add a way to archive/unarchive an item and visually
   distinguish archived items, following the existing UI patterns in that screen.

Definition of done — and how to check each one, not just assert it:
- Migration applies cleanly: actually run `alembic upgrade head` against a real,
  migrated-from-scratch database. Don't infer this from the generated file looking
  right.
- New endpoints respect the same ownership/superuser rules as the other item routes.
- Default item listing excludes archived items; `include_archived=true` includes them.
- Frontend client and UI reflect the change (no hand-edited generated client files).
- Existing tests still pass; add backend tests for the new behavior.
- **The UI actually works, not just compiles**: if this repo has Playwright specs
  under `frontend/tests/`, run them, or at minimum add/extend a spec that clicks the
  new archive/unarchive control and asserts the item's visual state changes. A
  passing backend test suite does not verify the button you added does anything —
  confirm the end-to-end behavior a real user would see, not just that the code
  compiles and unit tests are green.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline: each time you finish a distinct phase
   (e.g. "explored repo", "read Item model", "wrote migration", "added archive
   endpoint", "added unarchive endpoint", "updated list endpoint", "regenerated
   frontend client", "updated UI", "ran backend tests", "ran e2e/Playwright check"),
   append one line to that timeline with a timestamp
   (`date -u +%FT%TZ`) and a short label. If any gap between two consecutive
   timeline events exceeds 5 minutes, record what you were doing/waiting on during
   that gap — don't let it pass silently.
3. Keep a running tally of tool calls by type as you go (file reads, file edits/writes,
   bash commands, searches/greps) — don't reconstruct this from memory at the end,
   increment it as you actually use each tool.
4. Also note: the timestamp of your *first* file edit/write (as distinct from
   read/explore actions) — this is "time to first edit," a proxy for how long
   orientation took before you started producing the change.
5. When the task is complete (or if you give up / hit a blocker you can't resolve),
   run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-skill",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": [...],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "definition_of_done": {"<each checklist item as a short key>": true/false, "e2e_ui_behavior_verified": true/false},
  "docs_consulted": ["any docs/skill files you found and read along the way (besides source code), and how you found out they existed"],
  "blockers_hit": ["one line per blocker, e.g. bugs you had to work around, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "anything relevant to how you approached orientation in this repo, including any docs/skill files that turned out to help or not"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there)
   before your final commit, so it stays untracked and doesn't appear in the feature
   diff.
```

## Prompt: `repo-agent-recommended`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: add "archive" (soft-delete) support for Items.

Requirements:
1. Add an `is_archived: bool` field to the Item table, default `false`, with a proper
   Alembic migration (don't rely on auto-create-all).
2. Add `POST /api/v1/items/{id}/archive` — sets `is_archived = true`. Same ownership
   rules as the existing item endpoints (owner or superuser only).
3. Add `POST /api/v1/items/{id}/unarchive` — sets it back to `false`. Same auth rules.
4. `GET /api/v1/items/` should exclude archived items by default, but accept an
   `include_archived: bool = false` query param to include them.
5. Regenerate the frontend's API client so it reflects the new endpoints/field.
6. In the frontend Items UI, add a way to archive/unarchive an item and visually
   distinguish archived items, following the existing UI patterns in that screen.

Definition of done — and how to check each one, not just assert it:
- Migration applies cleanly: actually run `alembic upgrade head` against a real,
  migrated-from-scratch database. Don't infer this from the generated file looking
  right.
- New endpoints respect the same ownership/superuser rules as the other item routes.
- Default item listing excludes archived items; `include_archived=true` includes them.
- Frontend client and UI reflect the change (no hand-edited generated client files).
- Existing tests still pass; add backend tests for the new behavior.
- **The UI actually works, not just compiles**: if this repo has Playwright specs
  under `frontend/tests/`, run them, or at minimum add/extend a spec that clicks the
  new archive/unarchive control and asserts the item's visual state changes. A
  passing backend test suite does not verify the button you added does anything —
  confirm the end-to-end behavior a real user would see, not just that the code
  compiles and unit tests are green.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline: each time you finish a distinct phase
   (e.g. "explored repo", "read Item model", "wrote migration", "added archive
   endpoint", "added unarchive endpoint", "updated list endpoint", "regenerated
   frontend client", "updated UI", "ran backend tests", "ran e2e/Playwright check"),
   append one line to that timeline with a timestamp
   (`date -u +%FT%TZ`) and a short label. If any gap between two consecutive
   timeline events exceeds 5 minutes, record what you were doing/waiting on during
   that gap — don't let it pass silently.
3. Keep a running tally of tool calls by type as you go (file reads, file edits/writes,
   bash commands, searches/greps) — don't reconstruct this from memory at the end,
   increment it as you actually use each tool.
4. Also note: the timestamp of your *first* file edit/write (as distinct from
   read/explore actions) — this is "time to first edit," a proxy for how long
   orientation took before you started producing the change.
5. When the task is complete (or if you give up / hit a blocker you can't resolve),
   run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-recommended",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": [...],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "definition_of_done": {"<each checklist item as a short key>": true/false, "e2e_ui_behavior_verified": true/false},
  "docs_consulted": ["any docs/skill files you found and read along the way (besides source code), and how you found out they existed"],
  "blockers_hit": ["one line per blocker, e.g. bugs you had to work around, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "anything relevant to how you approached orientation in this repo, including any docs/skill files that turned out to help or not"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there)
   before your final commit, so it stays untracked and doesn't appear in the feature
   diff.
```

---

# Task A — Understanding (no code change)

Answer these five questions about the codebase, in order, by writing to `ANSWER.md`
at the repo root. **Do not edit any other file.** This task tests comprehension only.

1. Trace a request to `GET /api/v1/items/` end-to-end: name every file and function
   involved, in order, and explain precisely how the results differ for a superuser
   vs. a non-superuser.
2. What does `custom_generate_unique_id` in `backend/app/main.py` do, and what would
   the generated TypeScript client's function names look like if it were removed?
3. If `Item.owner_id`'s `ondelete="CASCADE"` were removed from
   `backend/app/models.py`, what would break, and name the exact existing test
   function that would catch the regression.
4. Why does `crud.authenticate` in `backend/app/crud.py` call `verify_password`
   against a `DUMMY_HASH` even when the user isn't found?
5. Name the exact mechanism (file + pattern) that stops a non-owner from reading
   someone else's Item via `GET /items/{id}`.

## Prompt: `repo-baseline`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: answer the following five questions about this codebase by writing your
answers to a new file, ANSWER.md, at the repo root. Do not edit any other file —
this task is comprehension only, not a code change. Be precise: name exact files,
functions, and line-level behavior where relevant, not general descriptions.

1. Trace a request to `GET /api/v1/items/` end-to-end: name every file and function
   involved, in order, and explain precisely how the results differ for a superuser
   vs. a non-superuser.
2. What does `custom_generate_unique_id` in `backend/app/main.py` do, and what would
   the generated TypeScript client's function names look like if it were removed?
3. If `Item.owner_id`'s `ondelete="CASCADE"` were removed from
   `backend/app/models.py`, what would break, and name the exact existing test
   function that would catch the regression.
4. Why does `crud.authenticate` in `backend/app/crud.py` call `verify_password`
   against a `DUMMY_HASH` even when the user isn't found?
5. Name the exact mechanism (file + pattern) that stops a non-owner from reading
   someone else's Item via `GET /items/{id}`.

Work through this yourself — explore the codebase as needed.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline: each time you finish answering one
   question, append one line with a timestamp (`date -u +%FT%TZ`) and which
   question number you just answered. If any gap between two consecutive timeline
   events exceeds 5 minutes, record what you were doing during that gap.
3. Keep a running tally of tool calls by type as you go (file reads, bash commands,
   searches/greps) — don't reconstruct this from memory at the end.
4. Note the timestamp of your first write to ANSWER.md — this is "time to first
   edit" for this task (should be late, since you're meant to research before
   writing here).
5. When done, run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-baseline",
  "task": "understanding",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": ["ANSWER.md"],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "questions_answered": <int, out of 5>,
  "docs_consulted": [],
  "blockers_hit": ["one line per blocker, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "how confident are you in each answer, and why"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there).
```

---

## Prompt: `repo-agent-optimised`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

This repo has an agent-oriented documentation layer on top of the application code.
Start by reading AGENTS.md at the repo root — it's the entry point and links to:
- docs/ard/ (Architecture Decision Records — why things are built the way they are)
- docs/api/openapi.json (the real, current API schema)
- okf/ (Open Knowledge Format docs — what each service, DB table, and router does,
  cross-linked)
Use these as your primary source of truth before reading raw source.

Task: answer the following five questions about this codebase by writing your
answers to a new file, ANSWER.md, at the repo root. Do not edit any other file —
this task is comprehension only, not a code change. Be precise: name exact files,
functions, and line-level behavior where relevant, not general descriptions.

1. Trace a request to `GET /api/v1/items/` end-to-end: name every file and function
   involved, in order, and explain precisely how the results differ for a superuser
   vs. a non-superuser.
2. What does `custom_generate_unique_id` in `backend/app/main.py` do, and what would
   the generated TypeScript client's function names look like if it were removed?
3. If `Item.owner_id`'s `ondelete="CASCADE"` were removed from
   `backend/app/models.py`, what would break, and name the exact existing test
   function that would catch the regression.
4. Why does `crud.authenticate` in `backend/app/crud.py` call `verify_password`
   against a `DUMMY_HASH` even when the user isn't found?
5. Name the exact mechanism (file + pattern) that stops a non-owner from reading
   someone else's Item via `GET /items/{id}`.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline: each time you finish answering one
   question, append one line with a timestamp (`date -u +%FT%TZ`) and which
   question number you just answered. If any gap between two consecutive timeline
   events exceeds 5 minutes, record what you were doing during that gap.
3. Keep a running tally of tool calls by type as you go (file reads, bash commands,
   searches/greps) — don't reconstruct this from memory at the end.
4. Note the timestamp of your first write to ANSWER.md — this is "time to first
   edit" for this task (should be late, since you're meant to research before
   writing here).
5. When done, run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-optimised",
  "task": "understanding",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": ["ANSWER.md"],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "questions_answered": <int, out of 5>,
  "docs_consulted": ["which of AGENTS.md / docs/ard/* / docs/api/openapi.json / okf/* you actually opened, and roughly how you used each"],
  "blockers_hit": ["one line per blocker, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "how confident are you in each answer, and why; how much the docs helped for a pure comprehension task specifically"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there).
```

---

## Prompt: `repo-agent-skill`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: answer the following five questions about this codebase by writing your
answers to a new file, ANSWER.md, at the repo root. Do not edit any other file —
this task is comprehension only, not a code change. Be precise: name exact files,
functions, and line-level behavior where relevant, not general descriptions.

1. Trace a request to `GET /api/v1/items/` end-to-end: name every file and function
   involved, in order, and explain precisely how the results differ for a superuser
   vs. a non-superuser.
2. What does `custom_generate_unique_id` in `backend/app/main.py` do, and what would
   the generated TypeScript client's function names look like if it were removed?
3. If `Item.owner_id`'s `ondelete="CASCADE"` were removed from
   `backend/app/models.py`, what would break, and name the exact existing test
   function that would catch the regression.
4. Why does `crud.authenticate` in `backend/app/crud.py` call `verify_password`
   against a `DUMMY_HASH` even when the user isn't found?
5. Name the exact mechanism (file + pattern) that stops a non-owner from reading
   someone else's Item via `GET /items/{id}`.

Work through this yourself — explore the codebase as needed.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline: each time you finish answering one
   question, append one line with a timestamp (`date -u +%FT%TZ`) and which
   question number you just answered. If any gap between two consecutive timeline
   events exceeds 5 minutes, record what you were doing during that gap.
3. Keep a running tally of tool calls by type as you go (file reads, bash commands,
   searches/greps) — don't reconstruct this from memory at the end.
4. Note the timestamp of your first write to ANSWER.md — this is "time to first
   edit" for this task (should be late, since you're meant to research before
   writing here).
5. When done, run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-skill",
  "task": "understanding",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": ["ANSWER.md"],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "questions_answered": <int, out of 5>,
  "docs_consulted": ["any docs/skill files you found and read along the way (besides source code), and how you found out they existed"],
  "blockers_hit": ["one line per blocker, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "how confident are you in each answer, and why; whether any docs/skill files you found helped for a pure comprehension task specifically"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there).
```

## Prompt: `repo-agent-recommended`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: answer the following five questions about this codebase by writing your
answers to a new file, ANSWER.md, at the repo root. Do not edit any other file —
this task is comprehension only, not a code change. Be precise: name exact files,
functions, and line-level behavior where relevant, not general descriptions.

1. Trace a request to `GET /api/v1/items/` end-to-end: name every file and function
   involved, in order, and explain precisely how the results differ for a superuser
   vs. a non-superuser.
2. What does `custom_generate_unique_id` in `backend/app/main.py` do, and what would
   the generated TypeScript client's function names look like if it were removed?
3. If `Item.owner_id`'s `ondelete="CASCADE"` were removed from
   `backend/app/models.py`, what would break, and name the exact existing test
   function that would catch the regression.
4. Why does `crud.authenticate` in `backend/app/crud.py` call `verify_password`
   against a `DUMMY_HASH` even when the user isn't found?
5. Name the exact mechanism (file + pattern) that stops a non-owner from reading
   someone else's Item via `GET /items/{id}`.

Work through this yourself — explore the codebase as needed.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline: each time you finish answering one
   question, append one line with a timestamp (`date -u +%FT%TZ`) and which
   question number you just answered. If any gap between two consecutive timeline
   events exceeds 5 minutes, record what you were doing during that gap.
3. Keep a running tally of tool calls by type as you go (file reads, bash commands,
   searches/greps) — don't reconstruct this from memory at the end.
4. Note the timestamp of your first write to ANSWER.md — this is "time to first
   edit" for this task (should be late, since you're meant to research before
   writing here).
5. When done, run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-recommended",
  "task": "understanding",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": ["ANSWER.md"],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "questions_answered": <int, out of 5>,
  "docs_consulted": ["any docs/skill files you found and read along the way (besides source code), and how you found out they existed"],
  "blockers_hit": ["one line per blocker, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "how confident are you in each answer, and why; whether any docs/skill files you found helped for a pure comprehension task specifically"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there).
```

---

# Task B — Simple change (sortable item listing)

Add optional sorting to `GET /api/v1/items/`. Single-concern, single-file-ish,
no migration, no frontend change — meant to isolate orientation cost from
implementation cost.

## Prompt: `repo-baseline`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: add optional sorting to the item listing endpoint.

Requirements:
1. Add an `order_by: Literal["created_at", "title"] = "created_at"` query parameter
   to `read_items` in `backend/app/api/routes/items.py`.
2. When `order_by="title"`, order results by `Item.title` ascending. When omitted or
   `"created_at"`, keep the existing behavior unchanged (ordered by `created_at`
   descending).
3. No migration needed — no schema change. No frontend change needed; do not
   regenerate the frontend client for this task, it's out of scope.
4. Add a backend test verifying both orderings return items in the correct order.

Definition of done:
- Existing backend tests still pass; the new test passes.
- No migration file created. No frontend files touched.

Work through this yourself — explore the codebase as needed and match its existing
conventions.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline with timestamps (`date -u +%FT%TZ`) for each
   distinct phase (explored repo, first edit, wrote test, ran tests, done). If any
   gap between two consecutive events exceeds 5 minutes, record what you were doing.
3. Keep a running tally of tool calls by type as you go — don't reconstruct this
   from memory at the end.
4. Note the timestamp of your first file edit/write (distinct from read/explore).
5. When done, run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-baseline",
  "task": "simple_change",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": [...],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "definition_of_done": {"order_by_param_added": true/false, "title_ordering_correct": true/false, "default_ordering_unchanged": true/false, "new_test_added_and_passes": true/false, "no_migration_created": true/false, "no_frontend_touched": true/false},
  "docs_consulted": [],
  "blockers_hit": ["one line per blocker, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "anything relevant to how easy or hard orientation was for a small, scoped change in this repo"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there).
```

---

## Prompt: `repo-agent-optimised`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

This repo has an agent-oriented documentation layer on top of the application code.
Start by reading AGENTS.md at the repo root — it's the entry point and links to:
- docs/ard/ (Architecture Decision Records — why things are built the way they are)
- docs/api/openapi.json (the real, current API schema)
- okf/ (Open Knowledge Format docs — what each service, DB table, and router does,
  cross-linked)
Use these as your primary source of truth before reading raw source.

Task: add optional sorting to the item listing endpoint.

Requirements:
1. Add an `order_by: Literal["created_at", "title"] = "created_at"` query parameter
   to `read_items` in `backend/app/api/routes/items.py`.
2. When `order_by="title"`, order results by `Item.title` ascending. When omitted or
   `"created_at"`, keep the existing behavior unchanged (ordered by `created_at`
   descending).
3. No migration needed — no schema change. No frontend change needed; do not
   regenerate the frontend client for this task, it's out of scope.
4. Add a backend test verifying both orderings return items in the correct order.

Definition of done:
- Existing backend tests still pass; the new test passes.
- No migration file created. No frontend files touched.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline with timestamps (`date -u +%FT%TZ`) for each
   distinct phase (read docs, explored repo, first edit, wrote test, ran tests,
   done). If any gap between two consecutive events exceeds 5 minutes, record what
   you were doing.
3. Keep a running tally of tool calls by type as you go — don't reconstruct this
   from memory at the end.
4. Note the timestamp of your first file edit/write (distinct from read/explore).
5. When done, run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-optimised",
  "task": "simple_change",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": [...],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "definition_of_done": {"order_by_param_added": true/false, "title_ordering_correct": true/false, "default_ordering_unchanged": true/false, "new_test_added_and_passes": true/false, "no_migration_created": true/false, "no_frontend_touched": true/false},
  "docs_consulted": ["which of AGENTS.md / docs/ard/* / docs/api/openapi.json / okf/* you actually opened, and roughly how you used each"],
  "blockers_hit": ["one line per blocker, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "how much the docs helped for a small, scoped change specifically — did reading AGENTS.md/ARD cost more than it saved for a change this size?"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there).
```

---

## Prompt: `repo-agent-skill`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: add optional sorting to the item listing endpoint.

Requirements:
1. Add an `order_by: Literal["created_at", "title"] = "created_at"` query parameter
   to `read_items` in `backend/app/api/routes/items.py`.
2. When `order_by="title"`, order results by `Item.title` ascending. When omitted or
   `"created_at"`, keep the existing behavior unchanged (ordered by `created_at`
   descending).
3. No migration needed — no schema change. No frontend change needed; do not
   regenerate the frontend client for this task, it's out of scope.
4. Add a backend test verifying both orderings return items in the correct order.

Definition of done:
- Existing backend tests still pass; the new test passes.
- No migration file created. No frontend files touched.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline with timestamps (`date -u +%FT%TZ`) for each
   distinct phase (read docs, explored repo, first edit, wrote test, ran tests,
   done). If any gap between two consecutive events exceeds 5 minutes, record what
   you were doing.
3. Keep a running tally of tool calls by type as you go — don't reconstruct this
   from memory at the end.
4. Note the timestamp of your first file edit/write (distinct from read/explore).
5. When done, run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-skill",
  "task": "simple_change",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": [...],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "definition_of_done": {"order_by_param_added": true/false, "title_ordering_correct": true/false, "default_ordering_unchanged": true/false, "new_test_added_and_passes": true/false, "no_migration_created": true/false, "no_frontend_touched": true/false},
  "docs_consulted": ["any docs/skill files you found and read along the way (besides source code), and how you found out they existed"],
  "blockers_hit": ["one line per blocker, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "whether any docs/skill files you found helped for a small, scoped change specifically"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there).
```

## Prompt: `repo-agent-recommended`

```
You're working in this repo: a FastAPI + SQLModel + PostgreSQL backend with a
React/TypeScript frontend (TanStack Router, generated API client).

Task: add optional sorting to the item listing endpoint.

Requirements:
1. Add an `order_by: Literal["created_at", "title"] = "created_at"` query parameter
   to `read_items` in `backend/app/api/routes/items.py`.
2. When `order_by="title"`, order results by `Item.title` ascending. When omitted or
   `"created_at"`, keep the existing behavior unchanged (ordered by `created_at`
   descending).
3. No migration needed — no schema change. No frontend change needed; do not
   regenerate the frontend client for this task, it's out of scope.
4. Add a backend test verifying both orderings return items in the correct order.

Definition of done:
- Existing backend tests still pass; the new test passes.
- No migration file created. No frontend files touched.

---
METRICS PROTOCOL (do this regardless of the task above — it does not count as part of
the deliverable and should not be committed):

1. Immediately, before doing anything else, run `date -u +%FT%TZ` and record it as
   `start_time`.
2. As you work, keep a running timeline with timestamps (`date -u +%FT%TZ`) for each
   distinct phase (read docs, explored repo, first edit, wrote test, ran tests,
   done). If any gap between two consecutive events exceeds 5 minutes, record what
   you were doing.
3. Keep a running tally of tool calls by type as you go — don't reconstruct this
   from memory at the end.
4. Note the timestamp of your first file edit/write (distinct from read/explore).
5. When done, run `date -u +%FT%TZ` for `end_time`, then write a single JSON file to
   `RUN_METRICS.json` at the repo root with this shape:

{
  "repo": "repo-agent-recommended",
  "task": "simple_change",
  "start_time": "...",
  "end_time": "...",
  "duration_seconds": <int>,
  "time_to_first_edit_seconds": <int>,
  "tool_calls": {"read": <int>, "edit_or_write": <int>, "bash": <int>, "search_or_grep": <int>, "other": <int>, "total": <int>},
  "files_read": [...],
  "files_created_or_edited": [...],
  "timeline": [{"time": "...", "event": "..."}, ...],
  "definition_of_done": {"order_by_param_added": true/false, "title_ordering_correct": true/false, "default_ordering_unchanged": true/false, "new_test_added_and_passes": true/false, "no_migration_created": true/false, "no_frontend_touched": true/false},
  "docs_consulted": ["any docs/skill files you found and read along the way (besides source code), and how you found out they existed"],
  "blockers_hit": ["one line per blocker, or any >5min gap and why"],
  "self_assessed_completion": "complete | partial | blocked",
  "notes": "whether any docs/skill files you found helped for a small, scoped change specifically"
}

6. Add `RUN_METRICS.json` to `.gitignore` (create the entry if it's not already there).
```

---

## Interpreting `RUN_METRICS.json`

Treat it as a self-report to sanity-check, not ground truth — across 3 runs so far,
self-reported completion has been wrong (always pessimistically) in 3 of 6
individual agent-runs, always due to local environment friction, never a real code
defect:

- Cross-check `tool_calls.total` and the `timeline` roughly against the actual
  transcript length for that run.
- **Independently re-verify correctness yourself, after the run, without touching
  what the agent did.** On a copy of the repo's final state, on your own fresh,
  isolated database (never the one the agent used, never handed back to it): run the
  migration, run the backend test suite, and — per the strengthened Definition of
  done above — actually exercise the new behavior (hit the live API, or run/read the
  Playwright spec) rather than trusting `definition_of_done` or
  `self_assessed_completion` at face value. This is scoring, not scaffolding: it
  happens after the agent's session is over and never feeds back into what the agent
  saw or did.
- For the real token total, don't trust anything the agent writes about its own
  usage — it has no visibility into that number from inside a turn. Instead run
  `python3 token_usage.py --cwd <repo path>` (in this directory) right after the
  session ends, before resetting: it reads the real cumulative usage straight out of
  the agent tool's own session transcript.
    - Codex CLI: reads `~/.codex/sessions/.../rollout-*.jsonl`'s `token_usage_record`
      events directly (this is what's wired up right now).
    - Claude Code: transcripts live at
      `~/.claude/projects/<project-slug>/<session-id>.jsonl` with a `usage` block per
      assistant turn instead — same idea, different field names; `token_usage.py`
      would need a small branch added if you switch tools.
  Paste the result into the matching `RUN_METRICS.json` as a `_real_token_usage_verified`
  block (see `RUN_METRICS_baseline_run2.json` / `RUN_METRICS_optimised_run2.json` for
  the shape) rather than trusting a self-reported figure.
- `docs_consulted`, `time_to_first_edit_seconds`, and the real token total are
  probably the most interesting fields for judging whether a given doc layer earned
  its keep. With `repo-agent-skill` in the mix, compare it against
  `repo-agent-optimised` specifically — they share the same OKF layer, so any
  difference between those two isolates the effect of *how-to* vs *why* guidance,
  while comparing either against `repo-baseline` shows the effect of having
  agent-oriented docs at all.
