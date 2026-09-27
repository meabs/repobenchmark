# Benchmark fixture: baseline vs. two agent-optimised repos

This directory holds three repos with byte-identical application code, used to
compare how efficiently an AI agent can get a real task done end-to-end with no
agent-oriented docs, with a "why"-oriented layer, or with a "how"-oriented layer.

## Source

- Repo: [fastapi/full-stack-fastapi-template](https://github.com/fastapi/full-stack-fastapi-template)
- Commit: `cb740b656d7a0a6c5e12c7bf8e50343ec94ee9c7` (`master` at clone time)
- Cloned: 2026-09-24
- License: MIT

FastAPI + SQLModel + PostgreSQL backend, React/TypeScript frontend, Docker Compose
deployment, Alembic migrations, JWT auth. Chosen for being real-world, actively
maintained, MIT-licensed, and small enough (~2.4MB source) to fully and accurately
annotate rather than gesture at.

## Normalization

Upstream ships `.agents/skills/` and `.claude/skills/` (pre-baked FastAPI/SQLModel
reference material for AI coding tools). Both directories were stripped from the shared
source tree **before** copying into either repo below, so neither repo is contaminated
by a third party's agent docs — the comparison is specifically about the documentation
layer added here, not upstream's.

`.github/`, `.vscode/`, `hooks/`, `packages/`, `img/`, and the human-written docs
(`README.md`, `CONTRIBUTING.md`, `development.md`, `deployment*.md`) were kept as
ordinary project scaffolding in both repos.

## The three repos

### `repo-baseline/`
The normalized source tree, `git init`, single commit. No agent-specific docs beyond
whatever upstream already ships as normal human-facing documentation.

### `repo-agent-optimised/`
Identical starting commit to `repo-baseline` (same tree — verified via `diff -rq`),
plus a follow-up commit adding:

- `AGENTS.md` — single entry point for an agent: directory map, how to run things,
  pointers into the rest of the layer.
- `docs/ard/` — 6 Architecture Decision Records, written by reading the actual source
  each one describes (not invented): SQLModel-unified models, JWT auth, Compose/Traefik
  topology, Alembic-owned schema, generated TS client, the env-gated `private` router.
- `docs/api/openapi.json` — the backend's real OpenAPI 3.1 schema, exported by
  importing the actual FastAPI `app` object and calling `app.openapi()` (not
  hand-written), using a Python 3.14 interpreter (the version this project pins).
- `okf/` — an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/open-knowledge-format)
  v0.2 bundle (markdown + YAML frontmatter, cross-linked, per the real Google spec):
  concept docs for each service, DB table, API router, and the deployment topology,
  plus `index.md`/`log.md`. Every concept doc carries v0.2 trust-signal fields
  (`generated`, `sources`) but deliberately no `verified` entry — see the corrections
  below and `repo-agent-optimised/okf/index.md`'s "Trust tier" section.

This repo answers "why is it built this way" (ARD) plus "what is everything and how
does it relate" (OKF).

### `repo-agent-skill/` (added 2026-09-25, ablation of `repo-agent-optimised`)
Same starting commit as the other two (verified via `diff -rq`, excluding `.env`'s
db name), plus a follow-up commit adding:

- `.agents/skills/fastapi-fullstack-workflow/SKILL.md` — a procedural playbook:
  step-by-step instructions for the kinds of changes this codebase typically needs
  (add a model field, write a migration, add an endpoint, regenerate the frontend
  client, add a UI action, verify the work is actually done), written as *how to do
  it*, not *why it's built this way*. A tiny `AGENTS.md` (pointers only, no
  directory map, no procedures) sends the agent here for "how" and to `okf/` for
  "what" — no `docs/ard/` in this repo. (Originally `SKILL.md` sat at the repo root
  with no `AGENTS.md` at all for rounds 1–4; restructured post-analysis — see
  Corrections below.)
- `okf/` — **the same OKF v0.2 bundle as `repo-agent-optimised`**, copied verbatim
  except for cross-references into `docs/ard/` (which doesn't exist here) — those
  were removed or redirected to the relevant `SKILL.md` section where the topic was
  actually procedural (e.g. "how to write a migration").
- `docs/api/openapi.json` — same static schema as `repo-agent-optimised`.

This repo answers "how do I do the kind of thing I'm about to do" (SKILL.md) plus
"what is everything and how does it relate" (OKF) — deliberately withholding the
"why" layer. Comparing this repo against `repo-agent-optimised` isolates the effect
of procedural vs. rationale guidance, since both share the identical OKF backbone;
comparing either against `repo-baseline` shows the effect of having agent-oriented
docs at all.

### `repo-agent-recommended/` (added 2026-09-25, our own synthesis)

Same starting commit as the other three (verified via `diff -rq`, excluding `.env`'s
db name), plus a follow-up commit adding a doc layer designed from what this study
had found up to that point, not from first principles:

- `AGENTS.md` and `.agents/skills/` (the same 6 task-scoped skills:
  `model-field-change`, `write-migration`, `add-api-endpoint`,
  `regenerate-frontend-client`, `add-ui-action`, `verify-work`) are copied verbatim
  from `repo-agent-skill` v3 — nothing about that layer was implicated in the one
  real, sign-consistent cost effect this study found, so there was no reason to
  change it.
- `docs/ard/` is deliberately absent. Auditing `repo-agent-optimised`'s 6 ARDs
  against `repo-agent-skill`'s OKF bundle found 4 of 6 facts (cascade-delete FK,
  env-gated private router, generated client, Alembic-over-`create_all`) already
  fully restated in OKF's concept docs — exact duplication across artifacts, the
  failure mode an external design review flagged earlier in this session. The
  remaining 2 facts (the `DUMMY_HASH` timing-attack mitigation in
  `crud.authenticate`; `custom_generate_unique_id`'s short-client-name rationale)
  were genuinely missing from OKF and are the kind of fact an agent could
  plausibly regress (removing what looks like dead/wasteful code). Added as short
  notes inside the OKF concept doc each is actually attached to
  (`okf/routers/login.md`, `okf/services/backend.md`) rather than recreating a
  parallel "why" tree.
- Same no-prompt-hints treatment as `repo-agent-skill` v3 — its 3 task prompts in
  `prompt.md` are byte-identical to `repo-baseline`'s.

This repo tests a specific, falsifiable claim: that the token-cost premium
`repo-agent-optimised` paid on the simple-change task came from the always-loaded
`docs/ard/` layer specifically (not from OKF or from having *any* doc layer), and
that dropping it while keeping the two facts that were actually load-bearing
preserves correctness without paying that premium. Not yet run — see Benchmark runs
below once it has been.

## Verification performed

- `git log --oneline` in all three repos: one baseline commit each (the two
  agent-optimised repos each have a second, doc-only commit on top).
- All three repos' committed application code verified byte-identical to each other
  (via `git archive` of each repo's baseline commit into a temp dir, then
  `diff -rq`, excluding `.env`'s deliberately-different db name and each repo's own
  doc paths).
- `docs/api/openapi.json` validated as well-formed JSON; its 15 paths cross-checked
  against `backend/app/api/main.py`'s router includes and each route file.
- ARD, SKILL.md, and OKF docs written directly from the source files they describe,
  not from general FastAPI/SQLModel knowledge — file/line references were checked
  against the actual repo content. `repo-agent-skill`'s OKF bundle's YAML frontmatter
  re-validated after removing/redirecting its `docs/ard/` cross-references.

## Corrections

- **2026-09-24:** `repo-agent-optimised/AGENTS.md` originally claimed
  `backend/app/api/deps.py`'s `except InvalidTokenError, ValidationError:` was an
  upstream Python syntax bug. That was checked against the system's Python 3.13; the
  project actually pins Python ≥3.14, which added
  [PEP 758](https://peps.python.org/pep-0758/) and made that exact syntax valid. It
  was never a bug. Corrected in `AGENTS.md` and logged in `repo-agent-optimised/okf/log.md`.
  A first benchmark run (see below) had already been affected by the original, incorrect
  version of this doc — see the run report for what that cost.
- **2026-09-25:** the `okf/` bundle was upgraded from v0.1 to
  [v0.2](https://cloud.google.com/blog/products/data-analytics/okf-v0-2-adds-trust-signals)
  and fixed to actually match spec: `index.md`/`log.md` had been given full concept-doc
  frontmatter (`type`/`title`/`description`/`tags`), which v0.2 (and v0.1) reserve
  for concept docs only — non-root `index.md` and `log.md` should carry no
  frontmatter, and the bundle-root `index.md` only `okf_version`. All 11 concept
  docs gained `generated` and `sources` trust-signal fields (no `verified` — none of
  this bundle has had human sign-off). Also trimmed `AGENTS.md`, which had grown to
  duplicate `development.md`'s run instructions almost line for line — AGENTS.md now
  points there instead of repeating it.
- **2026-09-25:** discovered both repos' `.env` pointed `DATABASE_URL` at the same
  database name (`app`) on the same local Postgres — meaning two agent runs against
  the same local Postgres fallback (no Docker) would stamp each other's Alembic
  revision into a database the other repo also reads, causing a false "migration
  failed: unknown revision" for whichever ran second. Fixed: each repo's `.env` now
  points at its own db (`app_baseline` / `app_optimised` / `app_skill`), and
  `reset.sh` drops and recreates all of them between runs.
- **2026-09-25:** added `repo-agent-skill` and adopted two methodology fixes after
  reviewing runs 1–3: (1) launch future sessions in the agent tool's non-interactive/
  auto-approved mode, since at least one run's duration was inflated by idle time
  between human tool-approval prompts rather than agent work; (2) strengthened every
  prompt's Definition of Done to require actually exercising the new UI behavior
  (Playwright or a live request), not just a passing backend test suite — see
  `prompt.md`.
- **2026-09-25 (post-analysis):** restructured `repo-agent-skill`'s doc layer after
  external review of the general skill-vs-OKF design (not a data-affecting fix —
  applied after all 4 rounds were already collected and reported). The critique:
  a repo skill should be a *procedural adapter* ("how to do the task"), never
  another place that restates what things are — that's OKF's job — or the repo
  would reproduce the same content across `README.md`, `AGENTS.md`, OKF, and the
  skill. Two changes:
  1. Added a genuinely tiny `AGENTS.md` (5 pointer lines — no directory map, no
     procedures, no gotchas) that this repo previously lacked entirely. It does
     only navigation: "meaning lives in `okf/`, procedures live in the skill."
  2. Moved `SKILL.md` from the repo root to
     `.agents/skills/fastapi-fullstack-workflow/SKILL.md` — real skill-discovery
     location instead of a root-level doc — and trimmed its opening paragraph,
     which had started to duplicate `AGENTS.md`'s one-line "what this is."
  Declined the enterprise-platform parts of the review (`service.yaml`,
  `okf.lock.yaml`, cross-repo dependency resolution — none apply to a standalone
  repo) and declined the reviewer's own "router skill + N task skills" suggestion,
  since they flagged it as optional/aspirational and this repo's one 120-line
  `SKILL.md` doesn't approach the scale (they cited 5,000 lines) where that split
  earns its complexity.
  **This changes `repo-agent-skill`'s definition** — rounds 1–4's results
  (`SKILL.md` at root, no `AGENTS.md`) are not directly comparable to any future
  round run against this new structure; treat this as the start of a
  `repo-agent-skill` v2, not a fix to the existing dataset.

## Benchmark runs

Task prompts for all three repos live in `prompt.md`. Runs 1–3 below predate
`repo-agent-skill` (baseline vs. agent-optimised only) — future runs should include
all three. Each run produces a `RUN_METRICS.json` inside the repo it ran in
(gitignored — copy it out, e.g. to `RUN_METRICS_<label>.json` at this level, before
resetting).

**Run 1** (2026-09-24, commit `c0d922d` doc layer, before the correction above):
both repos correctly implemented the task (66/66 backend tests independently
re-verified in both), but the documentation layer didn't show a clear efficiency
win, and the `deps.py` doc error above caused a spurious "fix" in
repo-agent-optimised. Full write-up: `RUN_METRICS_baseline.json` /
`RUN_METRICS_optimised.json` at this level, and the generated report
(link only, not committed — was published to Claude Artifacts during that
session).

**Run 2** (2026-09-24, after the `deps.py` correction, before the DB-collision fix
above): both repos again independently verified as fully correct (62/62 and 60/60
backend tests respectively, migrations apply cleanly on a clean database), but both
agents' *own* migration attempts failed against the shared local `app` database —
the DB-collision bug documented above, discovered because of this run. Notable
non-metrics finding: repo-agent-optimised's frontend UI more fully matched the
"default excludes archived" requirement (a proper toggle, defaulting off) where
repo-baseline's UI unconditionally requested archived items with no way to hide
them again; repo-baseline wrote more granular backend tests. Full data:
`RUN_METRICS_baseline_run2.json` / `RUN_METRICS_optimised_run2.json` at this level.

**Run 3** (2026-09-25, first run against the corrected OKF v0.2 bundle and isolated
per-repo databases): both repos independently re-verified as fully correct again
(61/61 backend tests both), and this run's DB-isolation fix held — no cross-repo
migration collision. repo-agent-optimised's own run still self-reported "partial"
(a different, local snag: its sandboxed test DB had no migrated tables when it first
tried running tests) — another false negative, not a defect. Both frontends got the
archive/unarchive toggle right this time (run 2's gap didn't repeat). Real token
usage, pulled from each session's own Codex transcript with `token_usage.py`
(not self-reported): repo-baseline 4,553,081 tokens, repo-agent-optimised 7,430,973
— **63% more**, up from run 2's 31% gap. Full data: `RUN_METRICS_baseline_run3.json`
/ `RUN_METRICS_optimised_run3.json` at this level, each also carrying a
`_real_token_usage_verified` block.

**Two runs of real token data now agree in direction**: repo-agent-optimised has used
meaningfully more tokens than repo-baseline both times it's been measured, and the
gap widened. See the report for the full breakdown.

**Run 4** (2026-09-25, first run of all three repos, first under `gpt-5.6-luna`,
first fully unattended): executed via `codex exec -m gpt-5.6-luna -s
danger-full-access --ignore-user-config`, one repo at a time — three concurrent
attempts were OOM-killed by the OS, so this and future rounds run sequentially.
`--ignore-user-config` routes around a broken `[mcp_servers.openaiDeveloperDocs]`
entry in `~/.codex/config.toml` (has a `url` but no `command`, which this CLI
version rejects) without editing that file; `-s danger-full-access` was required
because `workspace-write` blocks loopback, and this task needs a real local
Postgres — confirmed by probe before committing to it.

All three repos independently re-verified as fully correct (61/61 backend tests,
clean migration, all three) — and for the first time, every self-report matched
that (no false "partial"s), plausibly because non-interactive full-access mode
removed the DB-approval blocker that caused every prior false negative. All three
also, for the first time, actually satisfied the strengthened e2e requirement: each
ran its Playwright suite and got 11/11, not just a passing backend test suite.

Real token usage (not self-reported): repo-baseline 4,143,697; repo-agent-optimised
8,665,008 (**+109%**); repo-agent-skill 7,260,819 (**+75%**). New: comparing the two
doc repos directly — same OKF layer, different partner doc — repo-agent-optimised
(AGENTS.md + ARD) used **19% more tokens** than repo-agent-skill (SKILL.md alone),
despite a comparably-sized implementation. First data point suggesting "why"
guidance costs more than "how" guidance even holding the knowledge-graph layer
constant. Full data: `RUN_METRICS_{baseline,optimised}_run4.json`,
`RUN_METRICS_skill_run4.json` at this level.

**Caveat:** run 4 changed model, sandbox/approval mode, the verification bar, and
the repo count all at once versus runs 1–3 — treat it as the start of a new,
more-rigorous series (n=1 under the new methodology), not a clean 4th point in the
old one. See the report's "What changed operationally in run 4" table.

**To run again (now 3 repos):** reset all three with `./reset.sh` (see below), then
for each repo run `codex exec --cd <repo> -m gpt-5.6-luna -s danger-full-access
--ignore-user-config - < prompt_<repo>.txt` **one at a time** (not concurrently —
see the OOM note above), then copy each `RUN_METRICS.json` out and run
`python3 token_usage.py --cwd <repo>` for all three before resetting again.

**Run 5 / task matrix** (2026-09-25): added two new task types alongside the
existing complex feature — `understanding` (5 fixed comprehension questions,
answered to `ANSWER.md`, no code touched) and `simple_change` (one query param on
one endpoint, no migration, no frontend) — see `prompt.md`'s Task A/B/C sections.
Built `run_cell.sh`, a one-invocation-per-cell orchestrator (reset → `codex exec`
with a hard timeout, since macOS has no `timeout` binary → task-aware independent
verification → real token usage via `token_usage.py` → one consolidated
`*.summary.json`) to keep this cheap to run repeatedly. Ran the new 2×3 grid (6
cells; the 3 complex-task cells were reused from the prior run rather than
re-collected, since settings were already identical) — all 6 independently
verified clean. One cell (`simple_change` × `repo-agent-skill`) was OOM-killed by
the OS on first attempt (general desktop memory pressure from other running apps,
not a script bug) and succeeded on retry. Finding: the doc layers' token cost
**flips sign with task size** — repo-agent-optimised used 18% *fewer* tokens than
baseline on the comprehension task, ~even on the simple change, and 109% *more*
on the complex feature; repo-agent-skill's curve is +21% / -12% / +75%, not as
clean. Comprehension-answer quality was uniformly excellent across all three
repos when graded against the real source — no repo produced a wrong answer, so
token cost (not correctness) was the only differentiator for that task type.
Raw data: `task-matrix-run5/` at this level (per-cell `RUN_METRICS.json`,
`.summary.json`, and `.ANSWER.md` where applicable).

**Run 6 / task matrix, repeated** (2026-09-25, same day, same settings): re-ran the
full fresh 3×3 grid (all 9 cells this time, not reusing complex-task data) to check
whether run 5's "cost scales with task size" pattern replicates. **It does not.**
3 of the 6 repo-vs-baseline comparisons flip sign between run 5 and run 6 under
identical settings (e.g. repo-agent-optimised's complex-task delta goes from +109%
to -8%; repo-agent-skill's from +75% to -46%). Also extended `token_usage.py` to
extract **real tool-usage counts** (not self-reported) from the transcript's
`custom_tool_call` events — cleanly splits into `file_edits` (apply_patch) vs.
`shell_execs` (tools.exec_command) — and confirmed token totals track real tool-call
counts closely within every cell, so the variance is genuine session-to-session
difference in how much work the agent did, not a token-accounting artifact. What
*did* replicate perfectly: all 18 cells (both rounds) independently verified
correct, and all 9 comprehension-answer sets (both rounds) scored 5/5 against the
real source, including catching a deliberate trap in question 3 both times. Hit and
resolved two more infrastructure snags collecting this data: `reset.sh` was cut off
mid-run once (verbose `node_modules` removal output on a very large frontend
install, not a script bug — re-running it, which is idempotent, completed the
skipped repo) and several stray Postgres databases the *agents themselves* created
during their own verification steps were left behind and manually cleaned up.
Raw data: `task-matrix-run6/` at this level.

**Rounds 3 &amp; 4 / task matrix, statistical pass** (2026-09-25, same day): ran two
more full 9-cell rounds (bringing every cell to n=4) to settle whether any
repo-vs-baseline direction is real or noise. Built `run_round.sh` (wraps
`run_cell.sh`, runs all 9 cells with a controllable, randomized repo order per
task group, fail-fast on any cell that doesn't verify) to make repeat rounds a
single invocation instead of nine. Also pinned `model_reasoning_effort=medium`
explicitly in `run_cell.sh` (previously left to the model's undocumented
default under `--ignore-user-config`) and added round-labelled output filenames
so repeat rounds don't clobber each other. One cell was killed by the 900s
watchdog ~58s after its own work had already finished and verified clean (a
false-positive fail-fast) — fixed by bumping timeouts (1200/1200/1800) and
changing `run_round.sh`'s pass/fail logic to trust independent verification
over the raw timeout flag; resumed the round from the failed cell rather than
restarting it. Both rounds otherwise ran clean.

**Result, with real statistics (paired per-round comparison, n=4):** of the six
repo-vs-baseline comparisons, exactly **one** holds the same sign across all
four rounds — repo-agent-optimised on the simple-change task, +19%/+44%/+55%/+43%
tokens (mean +40.3%, sd=15.5). The other five flip sign at least once; averaging
them would produce a number but not a meaningful one, since round-to-round
variance exceeds the effect size in every one of those five cases. Correctness
and comprehension-answer quality remained perfect across all 27 sessions (24/24
independently-verified code tasks, 12/12 comprehension answer sets correct on
every graded fact, including catching the question-3 trap every time).

**Real dollar costs added**, computed from real token counts (never
self-reported) at `gpt-5.6-luna`'s published standard-tier pricing — $0.20 /
$0.02 / $1.20 per 1M input / cached-input / output tokens, sourced from
OpenAI's public pricing page's raw pricing-table data (not a third-party
summary). Total cost of the entire 4-round, 27-session study: **$3.04**.

Raw data: `task-matrix-run-r3/`, `task-matrix-run-r4/` at this level, and
`task-matrix-master.json` (all 27 cells consolidated: tokens, tool calls, cost,
mean/stdev per cell). Final report — analysis only, real costs, no
environment-issues or recommendations sections per request:
https://claude.ai/artifact/1oKQFeFmtsFPoZYVB97jVw

**`repo-agent-skill-v2` rerun** (2026-09-25, same session, same settings): after
restructuring `repo-agent-skill`'s doc layer (tiny `AGENTS.md` added +
`SKILL.md` moved to `.agents/skills/fastapi-fullstack-workflow/SKILL.md` — see
Corrections above), re-ran only that one repo's 3 tasks for 4 fresh rounds
(`skillv2-r1`…`skillv2-r4`; `repo-baseline`/`repo-agent-optimised` untouched).
Called `repo-agent-skill-v2` in analysis to keep it distinguishable from
rounds 1–4's `repo-agent-skill` (old flat structure) data. All 12 sessions
verified clean (migrations + full backend test suite passing every round,
59–62 tests depending on round; all 4 comprehension answers present with zero
unexpected file changes) — correctness held again.

Cost/token comparison, v2 vs. the same 4-round bar used throughout this study:

| Task | v2 mean cost | v1-skill mean cost | baseline mean cost | v2 vs. baseline, sign-consistent 4/4? |
|---|---|---|---|---|
| Understanding | $0.0401 | $0.0432 | $0.0475 | No (-12%,-12%,+11%,-52%) |
| Simple change | $0.0341 | $0.0400 | $0.0415 | No (+15%,-38%,-30%,-0%) |
| Complex change | $0.1340 | $0.1450 | $0.1680 | No (+22%,-58%,-44%,+64%) |

v2's mean cost is lower than both `repo-baseline` and the old `repo-agent-skill`
on all three tasks (-7% to -20% vs. v1-skill; -16% to -20% vs. baseline), but
**none of the three v2-vs-baseline comparisons are sign-consistent across the 4
rounds**, and each task's v2 cost range overlaps both baseline's and v1-skill's
ranges — same noise-dominated pattern as the rest of this study. Restructuring
the doc layer did not produce a repeatable, round-to-round-stable effect at
n=4; it may simply be a lower-variance-favorable draw, same as run 5 vs. run 6
was for the original repos. Would need more rounds to tell.

Raw data: `task-matrix-skillv2/` at this level (12 cells' `RUN_METRICS.json`,
`.summary.json`, `.ANSWER.md`, plus `aggregated.json` with the mean/stdev/min/max
computed above).

## Resetting between runs

`reset.sh` restores all three repos to their exact committed baseline (discards all
agent changes, deletes caches/venvs/node_modules, `git clean -fdx`) so each run
starts from truly identical conditions:

```
./reset.sh          # full reset — also wipes .venv/node_modules (slower next install, but a clean rerun)
./reset.sh --fast   # keeps .venv/node_modules, only discards code changes (faster iteration, less rigorous)
```

Copy out each of the three repos' `RUN_METRICS.json` (and note anything else worth
keeping) *before* resetting — the script does not back anything up.

## Out of scope

No GitHub push (local repos only, per request). No evaluation harness — running an
agent against each repo and comparing results is a separate future step.
