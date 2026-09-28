# repobenchmark

**Does the shape of a codebase's documentation for an AI coding agent actually change how much a task costs?**

Six documentation-layer designs, built on top of the identical real-world application, tested against the same three tasks, the same model, the same settings — four independent rounds per design (eight for the final comparison) — with every number pulled from the model provider's own transcript, never the agent's self-report.

This repository is the complete, reproducible artefact: the four test-fixture repositories with their documentation layers, the orchestration scripts that ran every session, and the raw + consolidated results data behind every number in the analysis below.

> **Update, 28 Sep 2026 — external validity.** The recommended layout was re-tested on **five real open-source codebases** (Python/Django, Spring Boot, React, .NET event-driven, legacy XML Spring), 30 Codex cells plus a 12-cell Cursor cross-tool pilot, with every saved comprehension answer graded against the source. The layout is unchanged, but the claim is narrower: it is **cheaper for understanding a codebase, mixed for changing one**, and generated doc layers contained factual errors that must be verified. Details: [External-validity study](#external-validity-study-five-real-codebases). Everything is under [`multi-repo-study/`](multi-repo-study/).

---

## Contents

- [The question](#the-question)
- [Key terms](#key-terms)
- [The six designs](#the-six-designs)
- [Methodology](#methodology)
- [Findings](#findings)
- [External-validity study: five real codebases](#external-validity-study-five-real-codebases)
- [The recommendation](#the-recommendation)
- [Repository layout](#repository-layout)
- [Reproducing this study](#reproducing-this-study)
- [Results data reference](#results-data-reference)
- [Provenance & licensing](#provenance--licensing)

---

## The question

When an AI coding agent is dropped into an unfamiliar codebase and asked to make a change, it has to work out — on its own — what the code does and how to change it safely. Every team that adopts AI coding agents ends up asking the same question, usually by intuition rather than evidence:

> Should the documentation written *for the agent* be a long entry-point file it's told to read up front, or a short index that lets it fetch only what a given task actually needs?

This project answers that question empirically rather than by intuition, by building six different answers into six copies of the same real application and measuring what each one actually costs.

## Key terms

| Term | Plain-English meaning |
|---|---|
| **`AGENTS.md`** | The one file an agent reads first, before anything else. In the heavier designs, a long page explaining the whole project. In the recommended design, a name and one-line description for each other document — nothing more. |
| **OKF (Open Knowledge Format)** | Short, structured reference pages describing what things *are* and how they connect — this table holds this data, this code talks to that code. A reference manual, not an instruction manual. Spec: [GoogleCloudPlatform/knowledge-catalog](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) v0.2. |
| **A skill** | A short, focused how-to guide for one kind of job — "how to add a database field." Six small guides rather than one long manual, each labelled clearly enough that an agent can tell from the label alone whether it's relevant. |
| **Gradual disclosure** | Offer a short index and let the agent fetch only the piece relevant to the task at hand, instead of handing it everything up front. |
| **Prescriptive vs. emergent prompt** | *Prescriptive*: the task prompt tells the agent exactly which doc file to read first. *Emergent*: the prompt says nothing about documentation at all — byte-identical to the plain baseline's prompt — so any doc-reading behaviour is genuinely unprompted discovery. This distinction is flagged against every result below; it is not a minor footnote. |
| **Sign-consistent** | A design was tested against baseline four (or eight) independent times. A result is only called *real* if it points the same direction — cheaper, or more expensive — every single time. If the direction flips even once, the round-to-round noise is at least as large as the effect, and the result cannot be trusted. This is the bar used throughout this study; it is never relaxed for any one design. |

## The six designs

| # | Design | What it actually is | Prompt regime |
|---|---|---|---|
| 1 | `repo-baseline` | The plain application. No documentation written for an agent at all. | — |
| 2 | `repo-agent-optimised` | A long, always-read `AGENTS.md` plus a full set of separate "why we built it this way" documents (architecture decision records), plus OKF. | Prescriptive |
| 3 | `repo-agent-skill` (v1) | One long how-to guide, no `AGENTS.md` at all, plus OKF. | Prescriptive |
| 4 | `repo-agent-skill` (v2) | Same long guide, now with a short `AGENTS.md` pointing to it. | Prescriptive |
| 5 | `repo-agent-skill` (v3) | The guide split into **six** narrow, single-purpose skills under `.agents/skills/`, with a tiny `AGENTS.md` index. The prompt mentions none of it. | **Emergent** |
| 6 | `repo-agent-recommended` | The same six skills and tiny index as v3, but the separate "why" documents are gone entirely — the two facts that were genuinely load-bearing were folded into the OKF page they belong to instead. | **Emergent** |

All six are built on the same pinned commit of [`fastapi/full-stack-fastapi-template`](https://github.com/fastapi/full-stack-fastapi-template) (`cb740b656d7a0a6c5e12c7bf8e50343ec94ee9c7`) — a FastAPI + SQLModel + PostgreSQL backend with a React/TypeScript frontend, JWT auth, Alembic migrations, and a generated API client. Their application code is verified byte-identical to each other; only the documentation layer differs. Full provenance, normalization steps, and the complete correction history are in [`SETUP.md`](SETUP.md).

## Methodology

**Three tasks**, run once per design per round:

| Task | What it asks for | Isolates |
|---|---|---|
| **Understanding** | Five fixed comprehension questions, answered to a file. No code touched. | Comprehension value, zero implementation noise. |
| **Simple change** | One query parameter added to one existing endpoint, plus a test. | Orientation cost from implementation cost — small enough that getting oriented should dominate the session. |
| **Complex change** | A full soft-delete feature: migration, two new endpoints, frontend UI, end-to-end test coverage. | The upper end of the difficulty range. |

**What's measured, and how:**

- **Tokens, tool calls, and dollar cost** are extracted directly from each session's own AI-provider transcript (`token_usage.py` reads the raw session log's `token_usage_record` and `custom_tool_call` events) — never the agent's self-report of what it did.
- **Dollar cost** is computed from those real token counts at the model's published standard-tier rate: $0.20 / 1M input tokens, $0.02 / 1M cached-input tokens, $1.20 / 1M output tokens.
- **Correctness** is independently re-verified after every session, not taken on trust: a fresh migration and full backend test run on a clean, isolated database for the two coding tasks; a diff check for zero unexpected file changes plus manual grading against the real source code for the comprehension task.
- **Every comparison uses four independent repeats (rounds) minimum** — eight for the final `recommended`-vs-`baseline` comparison — with the repo execution order randomized per round to control for cache-warming effects. A result is only called *real* if it holds the same sign in every round.
- **One constant across every session in this study, all six designs, including baseline:** the execution environment carries a pre-existing, repo-independent general-purpose skill catalogue, unrelated to this codebase, that every session had equal access to. It does not bias the *comparisons* between designs — it was present identically everywhere — but it means "emergent discovery" here means discovery of *this repo's own* documentation on top of that constant scaffold, not discovery by a completely blank agent.

## Findings

### Cost, by design, real dollars

Mean cost per session, at published standard-tier pricing:

| Design | Understanding | Simple change | Complex change |
|---|---:|---:|---:|
| `repo-baseline` | $0.0475 | $0.0415 | $0.1680 |
| `repo-agent-optimised` | $0.0448 | **$0.0534** | $0.1762 |
| `repo-agent-skill` v1 | $0.0432 | $0.0400 | $0.1450 |
| `repo-agent-skill` v2 | $0.0401 | $0.0341 | $0.1340 |
| `repo-agent-skill` v3 | $0.0459 | **$0.0379** | $0.1302 |
| `repo-agent-recommended` | $0.0453 | $0.0353 | $0.1189 |

### The only two proven effects in the whole study

Out of every design-vs-baseline comparison run (18 at n=4, plus 3 more at n=8 for `recommended`), only two held the same sign in every single round:

- **`repo-agent-optimised` is proven more expensive** on the simple-change task: **+19%, +44%, +55%, +43%** across four rounds (mean +40.3%). The always-loaded documentation costs more than it saves on a task this small.
- **`repo-agent-skill` v3 is proven cheaper** on the same task: **−1%, −17%, −3%, −10%** across four rounds. Same task, opposite design philosophy, opposite result.

This third, independent measure (tool-call count) confirms it: `repo-agent-optimised`'s simple-change tool-call count ranges **30–34** across all four rounds — entirely above `repo-baseline`'s **21–29**. The ranges do not touch.

### Discovery precision — 24 out of 24

`repo-agent-skill` v3 and `repo-agent-recommended` were tested with **zero mention** of `AGENTS.md`, OKF, or any skill anywhere in the prompt — including in the self-report template, since the prompt is read in full before the agent acts. Read directly from the real transcripts, across 24 sessions:

| Task | What it needs | Result |
|---|---|---|
| Understanding | No task skill | **8/8** — opened `AGENTS.md` + OKF, zero task skills |
| Simple change | Exactly 2 of 6 skills | **8/8** — opened exactly those two, never the other four |
| Complex change | All 6 skills | **8/8** — opened all six; the task genuinely touches every category |

The agent found its own documentation, every time, without being told it existed — and used exactly the relevant slice of it, never more.

### Correctness & comprehension — perfect, every design, every round

| Check | Result |
|---|---:|
| Migrations applied cleanly, independently re-verified on a fresh database | 64/64 |
| Backend test suites passing, independently re-verified | 64/64 |
| Comprehension answers present, zero unexpected file changes | 32/32 |
| Caught a deliberate regression trap in the source (no existing test catches it) | 32/32 |

No design ever traded correctness for speed or cost. Every difference measured in this study is a difference in *how much it cost to get there* — never in whether the agent got there.

### The n=8 stress test

`repo-agent-recommended` wasn't sign-consistent against baseline on any task at n=4 — since it's the design actually being recommended, that claim was stress-tested with four more rounds each for baseline and recommended (a coin-flip effect has a 1-in-8 chance of landing all-same-sign at n=4, but only 1-in-256 at n=8):

| Task | Result at n=8 |
|---|---|
| Understanding | 4/8 — an exact coin flip. No signal; more rounds won't help here. |
| Simple change | **7/8 cheaper** (two-sided binomial p ≈ 0.07) — a real pattern forming, just short of the conventional bar for proven. |
| Complex change | **7/8 cheaper** (p ≈ 0.07) — same result. |

**Straight answer: doubling did not produce proof on any task.** The recommendation below does not depend on it doing so.

## External-validity study: five real codebases

The six-design study used one codebase (the FastAPI template) that the documentation layers were designed on. To find out how much of the result travels, the **recommended** layout was generated for five unrelated, real open-source repositories and compared against a plain baseline of each. This part of the study is **n = 1 per cell** — directional, not proof.

**Design:** 5 repos × 2 arms (baseline / recommended) × 3 tasks (understanding / simple change / complex change) = **30 Codex cells** (`gpt-5.6-luna`), plus a **12-cell Cursor pilot** (`cursor-agent`, model `auto`) on two of the repos. All 30 Codex cells and all 12 Cursor cells pass their independent verification (after one documented doc-layer fix, below).

| Family | Repo (upstream) | Stack | Pinned upstream commit |
|---|---|---|---|
| python-api | [django-oscar](https://github.com/django-oscar/django-oscar) | Python · Django · dynamic class-loading | `0ae2005bad81254db837101e1977526ebe29cc1e` |
| java-spring | [spring-petclinic](https://github.com/spring-projects/spring-petclinic) | Java · Spring Boot 4 · JPA | `818c4136ea971c21674525f9053de0d9c7ad8cfe` |
| react-frontend | [bulletproof-react](https://github.com/alan2207/bulletproof-react) (`apps/react-vite`) | TypeScript · React · Vite | `9506629ed003a561c6627735480cce4994244bb4` |
| event-driven | [dotnet/eShop](https://github.com/dotnet/eShop) (Ordering) | C# · .NET · DDD/CQRS | `b4a40872005d4bb29e5b1fa1ff7e244143d39215` |
| legacy-enterprise | [spring-framework-petclinic](https://github.com/spring-petclinic/spring-framework-petclinic) | Java · plain Spring · XML config | `cd43fc08e272b778e1196d0754ab86d1d42f1d5a` |

The upstream codebases themselves are not vendored here; only the documentation layers, prompts, harness and results are (see [layout](#repository-layout)).

### Headline result — recommended vs baseline

| Task | Median token change | Repos cheaper | Mean token change | Median **dollar** change |
|---|---:|:---:|---:|---:|
| Understanding | **−33.8%** | 4 of 5 | −27.6% | −19.5% |
| Simple change | −6.6% | 3 of 5 | | −11.4% |
| Complex change | −20.1% | 3 of 5 | | −12.2% |
| **All 30 cells (dollars)** | | | | **$1.515 → $1.404 (−7.3%)** |

Per-repo token change (negative = recommended used fewer tokens):

| Repo | Understanding | Simple change | Complex change |
|---|---:|---:|---:|
| django-oscar | −33.5% | +17.8% | **+86.4%** |
| spring-petclinic | −33.8% | −14.5% | −64.3% |
| bulletproof-react | −44.3% | −6.6% | +3.6% |
| eShop (Ordering) | +16.9% | +16.7% | −34.0% |
| legacy petclinic | −43.2% | −48.2% | −20.1% |

**What generalized:** on comprehension the doc layer was cheaper on 4 of 5 codebases by a wide margin. **What did not:** the single-repo claim "never a cost penalty" does not hold as a universal. On code-change tasks the effect is real but repo-dependent; the worst cell cost +86% tokens (+61% dollars), the best −64% tokens.

**Token counts overstate dollar savings.** 89–98% of every run's input was served from cache (a tenth of the price), so priced at $0.20 / $0.02 / $1.20 per 1M fresh / cached / output tokens the honest overall saving is about **7%**, with direction depending on the codebase.

### Answer quality: the cheaper answers were not worse

The understanding tasks were originally checked only for "an answer file exists". All 14 saved answers were graded afterwards, blind and question by question against the real source (2 = correct and precise, 1 = partial, 0 = wrong), each set including a trap question.

| Repo | Baseline (of 10) | Recommended (of 10) |
|---|---:|---:|
| django-oscar | 10 | 10 |
| spring-petclinic | 8 | 9 |
| bulletproof-react | 9 | 9 |
| eShop | 9 | 10 |
| legacy petclinic | 10 | 9 |
| **Total** | **46** | **47** |

A tie: no sign the doc layer trades accuracy for cost. Cursor's four answers scored 10/10 (baseline) vs 9/10 (recommended). Grading was done by agent passes, so one-point differences are within grader judgement. Grader output, justifications and the doc errors found are in [`multi-repo-study/grading/`](multi-repo-study/grading/).

### Time and effort, not just tokens

Medians across the five repos, recommended vs baseline:

| Task | Wall time | Tool calls |
|---|---:|---:|
| Understanding | −11% | −23% |
| Simple change | −8% | +5% |
| Complex change | −3% | −17% |

Wall time is the noisiest measure (it also moves with machine load). The clear exception is django-oscar's complex task: 114 vs 62 tool calls, of which **95 vs 41 were reads/searches** and only 8 vs 12 were test runs, so the extra cost was reading, not testing.

### Discovery replicated: 15 of 15

Counting real commands in the session transcripts (not agent self-reports), every one of the 15 recommended Codex cells opened the documentation layer within its first four commands (all but one within its second), and the skills opened matched the task. Discovery is not the weak point; the *accuracy of what is discovered* is.

### The documentation itself contained errors

Grading also checked each recommended layer against the code. **Three of the five layers contained a factual error relevant to the tasks:** the Django offer skill describes a condition as a plain Python class (Oscar requires a proxy-model subclass) and registers it through the wrong mechanism; the React knowledge pages say the mock database persists to a file (it uses browser storage); the Spring entity skill says seed-data files need changes only for required columns (any new column breaks them). In two of three cases the agents answered correctly anyway, apparently by checking the code.

**Validity threat:** the recommended docs sometimes state test answers almost verbatim (the django-oscar trap answer, the React environment fix), because both the docs and the questions target each codebase's notable quirks. Treat the understanding saving as an **upper bound**.

### A real failure traced to the docs, then fixed and re-run

Two of the 30 cells failed independent verification on first attempt, both on `java-spring-recommended` (simple and complex change). The doc layer never mentioned two build-enforced conventions: a **code-formatting gate** and an **i18n sync test** (any new label in the default locale file must exist in every locale file). The baseline arm, with no doc layer, explored broadly enough to notice both and passed. The recommended arm trusted the narrower, more confident guidance and skipped that exploration. **An incomplete doc layer can make an agent overconfident.**

Fix: a new `verify-work` skill covering both conventions, logged in the bundle's `okf/log.md`; both cells re-run and passed.

| | Before | After |
|---|---|---|
| Simple change | FAIL (0 tests, build blocked), 1,213,000 tokens, 397s | PASS 56/56, 1,388,383 tokens (+14.5%), 332s |
| Complex change | FAIL (53/55), 2,017,083 tokens, 595s | PASS 55/55, 2,578,768 tokens (+27.9%), 498s |

**Caveat, stated plainly:** the first-attempt runs happened in a sandbox where the agent could not launch Maven at all, and the re-runs had a working Java toolchain. The pair changes two things at once, so the *cost of the fix is unmeasured*. What the evidence does support: the string `javaformat` never appears in either failed recommended transcript but appears 3 and 7 times in the matching baseline transcripts. To show both sides the study keeps the failed run and the fixed run.

### Cursor cross-tool checks

- **Original repo, 4 cells (understanding + simple change):** Cursor found the unmentioned `AGENTS.md` in 4 of 4 cells and opened exactly the two right skills on the simple change, but opened 3 unneeded skills on understanding (Codex opened none). Tokens within 1.3% of each other on simple change.
- **Five-repo pilot, 12 cells (react-frontend and java-spring, both arms, all tasks):** all 12 passed. Cursor's `total_tokens` excludes cache reads while Codex's includes them, so comparison uses fresh input + cached + output on both sides. Corrected, **10 of 12 cells land within ~0.6–1.3× of Codex**. The two outliers are both java-spring complex, in opposite directions (0.48× baseline, 2.75× recommended), which is n=1 run-to-run variance rather than a tool effect.

## The recommendation

**Ship `repo-agent-recommended`**: a tiny `AGENTS.md` index, six narrow task-scoped skills under `.agents/skills/`, and OKF with the load-bearing "why" facts folded into the relevant reference page — no separate architecture-decision-record tree.

Four reasons, all independent of the still-unconfirmed n=8 cost trend:

1. **No proven cost penalty anywhere.** `repo-agent-optimised` has one, proven, +40% on the simple-change task. `repo-agent-recommended` never replicates that on any task.
2. **Inherits proven discovery precision.** 24/24 correct, unprompted skill selections.
3. **Structurally the cleanest of the six.** Auditing `repo-agent-optimised`'s six architecture-decision records against OKF found four of six already fully duplicated as plain description — exact repetition across artefacts. The two genuinely load-bearing facts were moved into the OKF page they're actually attached to, instead of recreating a parallel "why" tree.
4. **Correctness and comprehension quality are tied for perfect** with every other design — this choice costs nothing on the one dimension every design already wins.

### Has the recommendation changed after the five-repo study?

**The layout is unchanged; the claims and conditions are narrower.**

- Expect roughly **20% cheaper in dollars on comprehension** tasks and about **10% on code changes**, not "never a penalty". Effects on code changes depend on the codebase, and one codebase cost 61% more in dollars on a complex change.
- **Treat every generated doc layer as unverified** until an agent has worked from it. 3 of 5 layers contained factual errors and one omission caused two failures.
- **Check what the build enforces** (formatters, sync tests, generated-code gates) and put it in a `verify-work` skill. That is the gap that failed cells.
- **Re-measure on your own codebase** before relying on the numbers here; the five-repo results are n=1 per cell.

## Repository layout

```
repobenchmark/
├── README.md                       this file
├── SETUP.md                        full provenance, normalization steps, correction history
├── prompt.md                       the exact task prompts used for every design × task combination
├── run_cell.sh                     runs one (design × task) session end to end: reset → agent run → verify → extract metrics
├── run_round.sh                    runs all nine cells of one round in a controlled, randomized order
├── reset.sh                        restores all four fixture repos to their committed baseline
├── token_usage.py                  extracts real token/tool-call usage from a session's raw transcript
│
├── repo-baseline/                  design 1 — no agent documentation at all
├── repo-agent-optimised/           design 2 — AGENTS.md + architecture decision records + OKF
├── repo-agent-skill/               design 5 (v3, current state) — six task-scoped skills, tiny AGENTS.md
├── repo-agent-recommended/         design 6 — the recommended layout
│
├── task-matrix-*/                  raw + consolidated results, single-repo study (see below)
│
├── multi-repo-study/               five-repo external-validity study + Cursor pilot
│   ├── doc-layers/<family>/        the recommended doc layer for each repo: AGENTS.md, .agents/skills/, okf/
│   ├── prompts/                    the exact prompt for every task × repo
│   ├── harness/                    run_multirepo_cell.sh, run_multirepo_cursor_cell.sh, rerun scripts, cursor_usage.py, progress logs
│   ├── results/codex/              per-cell summary, token usage, saved ANSWER.md, test logs (30 cells; the pre-fix java-spring runs are kept alongside as `*.attempt1_failed.*` and `*.preJavaFix.*`)
│   ├── results/cursor/             per-cell summary, usage, ANSWER.md, test logs (12 cells)
│   ├── grading/                    per-question grading of the saved comprehension answers, incl. doc errors found
│   ├── final_dataset.json          consolidated table: tokens, wall time, tool calls, verification, per cell
│   └── report/                     the full write-up: report.html and Doc-Layer-Study-Report.pdf
```

Each fixture repo ships its own `.env.example` (upstream's placeholder development values only — copy to `.env` and adjust before running).

## Reproducing this study

Requirements: a local PostgreSQL server, `uv` (Python), `bun` or `npm` (frontend), and an AI coding agent CLI capable of non-interactive execution (this study used OpenAI's `codex exec`).

```bash
# Reset every fixture repo to its clean, committed baseline (also drops/recreates each repo's own database)
./reset.sh

# Run a single cell: <repo> <task> <model> <timeout_seconds> <round_label>
./run_cell.sh repo-agent-recommended simple_change gpt-5.6-luna 1200 r1

# Run a full round (all 3 tasks x whichever repos you pass in a controlled order)
./run_round.sh r1 repo-baseline,repo-agent-recommended repo-baseline,repo-agent-recommended repo-baseline,repo-agent-recommended
```

`run_cell.sh` resets the target repo and its database, launches the agent non-interactively against the matching prompt in `prompt.md`, independently re-verifies the result (migration + test suite, or answer-file presence), extracts real usage via `token_usage.py`, and writes one consolidated `<cell>.summary.json`. Swap the model/CLI invocation inside `run_cell.sh` to reproduce this with a different agent.

### Reproducing the five-repo study

Clone each upstream repo at the commit pinned [above](#external-validity-study-five-real-codebases), create a `<family>-baseline` copy (upstream with its `.git` stripped) and a `<family>-recommended` copy (the same tree plus the matching `multi-repo-study/doc-layers/<family>/` contents), then:

```bash
bash multi-repo-study/harness/run_multirepo_cell.sh <family>-<arm> <understanding|simple_change|complex> ...      # Codex
bash multi-repo-study/harness/run_multirepo_cursor_cell.sh <family>-<arm> <task> auto 1200                        # Cursor
```

The scripts contain absolute paths from the original machine (`/Users/garry/...` and a session scratch directory); edit the `MULTI_DIR`/`SCRATCH` variables at the top before running. Verification needs Java 21 (Spring), Node + yarn (React), a Postgres/Django environment (Oscar) and the .NET SDK (eShop). Prompts are in `multi-repo-study/prompts/`.

## Results data reference

| Path | Contents |
|---|---|
| `task-matrix-run5/`, `task-matrix-run6/`, `task-matrix-run-r3/`, `task-matrix-run-r4/` | Rounds 1–4 for `repo-baseline`, `repo-agent-optimised`, `repo-agent-skill` v1 |
| `task-matrix-skillv2/` | 4 rounds, `repo-agent-skill` v2 |
| `task-matrix-skillv3clean/` | 4 rounds, `repo-agent-skill` v3 (clean run) |
| `task-matrix-recommended/` | Rounds 1–4, `repo-agent-recommended` |
| `task-matrix-n8-extension/` | Rounds 5–8, `repo-baseline` + `repo-agent-recommended` only (the n=8 stress test) |
| `task-matrix-master.json` | Consolidated: `repo-baseline`, `repo-agent-optimised`, `repo-agent-skill` v1 — per-cell tokens/tool-calls/cost, mean + stdev |
| `task-matrix-FINAL-VERIFIED.json` | All six designs, cross-checked against raw session files, tokens/tools/cost/wall-time |
| `task-matrix-v3-vs-recommended.json` | Head-to-head, skill v3 vs. recommended |
| `task-matrix-n8-tokens.json` | Raw per-round token data behind the n=8 stress test |

**Five-repo study** (`multi-repo-study/`): `final_dataset.json` is the consolidated table (`codex` list of 30 cells, `cursor` list of 12) with repo, arm, task, pass/fail, wall seconds, total tokens, tool calls and file edits. Per-cell raw files are in `results/`: `*.tokens.json` (real input / cached / output / reasoning tokens from the provider's own session log), `*.summary.json` (harness verdict), `*.ANSWER.md` (the saved comprehension answer that was graded), `*.test.log` (independent verification output). Raw agent transcripts are not included because of size.

Each single-repo round directory contains, per cell: `<task>__<repo>__<round>.summary.json` (consolidated result), `.RUN_METRICS.json` (the agent's own self-report, kept for comparison, never trusted on its own), and `.ANSWER.md` where applicable (the comprehension task's actual output).

## Provenance & licensing

- **Source application:** [`fastapi/full-stack-fastapi-template`](https://github.com/fastapi/full-stack-fastapi-template), MIT licensed, pinned at commit `cb740b656d7a0a6c5e12c7bf8e50343ec94ee9c7`.
- **Five-repo study sources:** the five upstream repositories listed [above](#external-validity-study-five-real-codebases), each under its own licence; none are vendored here, only the documentation layers written for them.
- **OKF specification:** [GoogleCloudPlatform/knowledge-catalog](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) v0.2.
- **This project's own work** — the four documentation layers, orchestration scripts, prompts, and results data — is MIT licensed; see [`LICENSE`](LICENSE).
- No API keys, credentials, or real secrets are present anywhere in this repository. Each fixture ships `.env.example` files carrying only the upstream template's own placeholder development values.
