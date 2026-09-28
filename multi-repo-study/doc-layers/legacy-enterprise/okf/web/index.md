---
type: concept
title: Web/controller layer
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - src/main/java/org/springframework/samples/petclinic/web/OwnerController.java
  - src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java
  - src/main/webapp/WEB-INF/jsp
---

# Web/controller layer

No Spring Boot here: `PetclinicInitializer` (a
`AbstractDispatcherServletInitializer`) replaces `web.xml`, programmatically
registering the root `ApplicationContext` (from `business-config.xml` +
`tools-config.xml`) and a servlet-level `ApplicationContext` (from
`mvc-core-config.xml`) plus a `CharacterEncodingFilter`. This is also where the
default repository-implementation Spring profile is set — see
`../repositories/index.md`.

Controllers (`OwnerController`, `PetController`, `VisitController`,
`VetController`, `CrashController`) live flat under `web/`, each `@Controller`-
annotated and constructor-injecting `ClinicService` — never a concrete repository
class directly, keeping controllers agnostic to which of the 3 repository
implementations is active.

Views are JSPs under `src/main/webapp/WEB-INF/jsp/<resource>/`, referenced from
controllers by string constants holding the view name (path relative to that
directory, no `.jsp` suffix) — see `../../.agents/skills/add-controller-page/SKILL.md`
for the full convention.
