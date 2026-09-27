#!/usr/bin/env bash
# Reset repo-baseline, repo-agent-optimised, and repo-agent-skill back to their
# committed baseline, so a fresh agent run starts from identical conditions every
# time.
#
# Usage:
#   ./reset.sh          full reset (default) — also deletes .venv/node_modules/caches
#                        (git clean -fdx), so the next run starts from a truly clean
#                        checkout, same as the very first run. Slower: the next agent
#                        run has to reinstall backend/frontend deps.
#   ./reset.sh --fast   keeps .venv/node_modules/caches, only discards tracked
#                        changes and new files (git clean -fd). Faster iteration,
#                        but not identical starting conditions to a fresh clone.
#
# Also drops and recreates each repo's local Postgres database (app_baseline /
# app_optimised / app_skill — see each repo's .env) if `psql`/`dropdb`/`createdb` are on PATH
# and a server is reachable at localhost:5432. This exists because run 2 of this
# benchmark discovered that leftover Alembic state in a shared local database
# (both repos used to point at the same db name, "app") silently blocked the
# *next* run's migration for both repos — a false "migration failed" that had
# nothing to do with either codebase. Skipped with a warning, not an error, if
# no local Postgres is reachable (e.g. you're using Docker Compose instead, in
# which case each repo's `docker compose up` already gets its own isolated db
# container and this step is unnecessary).
#
# Copy out anything you want to keep (esp. each repo's RUN_METRICS.json) BEFORE
# running this — it is not backed up.

set -euo pipefail

MODE="full"
if [[ "${1:-}" == "--fast" ]]; then
  MODE="fast"
elif [[ "${1:-}" != "" ]]; then
  echo "Unknown argument: $1 (expected --fast or nothing)" >&2
  exit 1
fi

BENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=(repo-baseline repo-agent-optimised repo-agent-skill)

# macOS ships bash 3.2 (no associative arrays), so map repo -> db name with a
# plain function instead of `declare -A`.
db_name_for() {
  case "$1" in
    repo-baseline) echo "app_baseline" ;;
    repo-agent-optimised) echo "app_optimised" ;;
    repo-agent-skill) echo "app_skill" ;;
    *) echo "" ;;
  esac
}

for repo in "${REPOS[@]}"; do
  dir="$BENCH_DIR/$repo"
  if [[ ! -d "$dir/.git" ]]; then
    echo "Skipping $repo — not a git repo at $dir" >&2
    continue
  fi

  echo "==> $repo ($MODE reset)"
  git -C "$dir" reset --hard HEAD

  if [[ "$MODE" == "full" ]]; then
    git -C "$dir" clean -fdx
  else
    git -C "$dir" clean -fd
  fi

  sha="$(git -C "$dir" rev-parse --short HEAD)"
  echo "    now at $sha, working tree clean"
done

echo
echo "==> local Postgres databases"
if command -v pg_isready >/dev/null 2>&1 && pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
  for repo in "${REPOS[@]}"; do
    db="$(db_name_for "$repo")"
    dropdb -h localhost --if-exists "$db" 2>/dev/null || true
    createdb -h localhost "$db"
    echo "    $db — dropped and recreated"
  done
else
  echo "    no local Postgres reachable at localhost:5432 — skipped"
  echo "    (fine if you're using docker compose; each repo gets its own db container there)"
fi

echo
echo "Done. All repos reset."
if [[ "$MODE" == "full" ]]; then
  echo "Full reset: .venv/node_modules were removed too — reinstall deps before the next run"
  echo "  (backend: cd <repo>/backend && uv sync | frontend: cd <repo>/frontend && bun install)."
fi
