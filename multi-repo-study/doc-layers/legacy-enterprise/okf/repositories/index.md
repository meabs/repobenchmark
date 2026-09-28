---
type: concept
title: Three repository implementations, one active by default
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - src/main/resources/spring/business-config.xml
  - src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java
  - src/test/java/org/springframework/samples/petclinic/service/ClinicServiceJpaTests.java
  - src/test/java/org/springframework/samples/petclinic/service/ClinicServiceSpringDataJpaTests.java
  - src/test/java/org/springframework/samples/petclinic/service/ClinicServiceJdbcTests.java
---

# Three repository implementations, one active by default

Four repository interfaces (`OwnerRepository`, `PetRepository`, `VetRepository`,
`VisitRepository`, directly under `repository/`) each have three implementations,
in sibling packages: `repository/jpa/`, `repository/jdbc/`,
`repository/springdatajpa/`. Which one is wired into a running application is a
**Spring profile**, selected in `business-config.xml`'s `<beans profile="...">`
blocks (not a Maven profile — Maven profiles in this repo only select the target
database vendor, e.g. H2 vs PostgreSQL).

## Which one is active by default

`PetclinicInitializer.java` sets the default Spring profile explicitly:

```java
private static final String SPRING_PROFILE = "jpa";
...
rootAppContext.getEnvironment().setDefaultProfiles(SPRING_PROFILE);
```

So a plain `mvn jetty:run` (or however the app is actually started, see
`../../readme.md`) uses **`repository/jpa/*`** — hand-written `@Repository` classes
using an injected `EntityManager` directly — not `repository/springdatajpa/*`
(interface-only Spring Data repositories, arguably the more "modern"-looking of the
three) and not `repository/jdbc/*` (hand-written SQL). It can be overridden with
`-Dspring.profiles.active=jdbc` or `=spring-data-jpa` at launch.

**This is easy to get backwards**: `spring-data-jpa` looks like the newest,
most-idiomatic choice, and someone skimming the package names might assume it's the
default. It isn't — `jpa` is.

## Why the test suite doesn't settle it either

All three implementations are exercised by the test suite, every run:
`ClinicServiceJpaTests`, `ClinicServiceSpringDataJpaTests`, and
`ClinicServiceJdbcTests` each `@ActiveProfiles(...)`-pin one profile and extend a
shared `AbstractClinicServiceTests` base, so `mvn test` passing tells you all three
implementations satisfy the same contract — it does **not** tell you which one the
deployed application actually uses. That's a separate fact, only findable in
`PetclinicInitializer`.

## Practical asymmetry between implementations

`repository/jpa/*` and `repository/springdatajpa/*` both map columns off the
entity classes' `@Column` annotations automatically — a new persisted field on a
model class needs no changes in either. `repository/jdbc/*` hand-writes every SQL
statement as `JdbcClient` text blocks (see e.g. `JdbcOwnerRepositoryImpl.save` and
`.findByLastName`) — a new field silently isn't read or written under the `jdbc`
profile unless every relevant SQL string is updated by hand. See
`../../.agents/skills/add-model-field/SKILL.md`.
