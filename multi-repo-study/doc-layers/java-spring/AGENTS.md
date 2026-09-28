# AGENTS.md

Spring Boot 4.1 + Spring Data JPA + Thymeleaf server-rendered app (spring-petclinic).
No frontend build, no REST API for the UI — controllers return view names. Read this
file first — it only points, it doesn't explain.

- **What things mean, and why they're built that way where it matters** (entities,
  controllers, schema init, test profiles — rationale folded into the relevant doc,
  not a separate ADR tree): [`okf/index.md`](okf/index.md).
- **How to do a specific kind of change**: `.agents/skills/` has one skill per task,
  each with its own scope — open the one(s) whose description matches what you're
  about to do, not all of them:
  - `add-entity-field` — add a field to an existing JPA entity (Owner/Pet/Vet/Visit),
    including the SQL schema change this repo requires (Hibernate DDL auto-gen is off)
  - `add-repository-query` — add a derived or `@Query` method to a Spring Data
    repository
  - `add-read-view` — add a new read-only page (controller + Thymeleaf template)
  - `run-full-profile-suite` — how to actually exercise the mysql/postgres
    Testcontainers-gated tests, not just the default H2 profile
  - `verify-work` — the build-blocking format gate and the i18n sync test that
    fail a change for reasons that have nothing to do with your change's logic;
    read this before considering any change done
- **Human setup/running instructions**: `README.md` — not duplicated here.

Nothing else lives in this file. If you find yourself adding an explanation or a
procedure here, it belongs in `okf/` or one of the skills instead.
