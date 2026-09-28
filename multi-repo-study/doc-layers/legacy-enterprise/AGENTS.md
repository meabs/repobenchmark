# AGENTS.md

Spring Framework (not Spring Boot) PetClinic: plain XML `ApplicationContext`
configuration, 3-layer architecture (web → service → repository). Read this file
first — it only points, it doesn't explain.

- **What things mean, and why they're built that way where it matters** (the 3
  repository implementations, the domain model, the web layer, and which pieces
  are actually active at runtime — rationale is folded into the relevant doc, not a
  separate tree): [`okf/index.md`](okf/index.md).
- **How to do a specific kind of change**: `.agents/skills/` has one skill per task,
  each with its own scope — open the one(s) whose description matches what you're
  about to do, not all of them:
  - `add-model-field` — add a field to a domain entity across all 3 repository
    implementations and all SQL dialects
  - `add-service-method` — add a method to `ClinicService`/`ClinicServiceImpl`
  - `add-controller-page` — add a new controller + JSP view
  - `run-the-right-tests` — which Maven/Spring-profile test class actually exercises
    the implementation you changed
- **Human setup/running instructions**: `readme.md` — not duplicated here.

Nothing else lives in this file. If you find yourself adding an explanation or a
procedure here, it belongs in `okf/` or one of the skills instead.
