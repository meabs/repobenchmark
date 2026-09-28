---
type: concept
title: Test profiles and Docker-gated integration tests
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:39:22Z
sources:
  - src/test/java/org/springframework/samples/petclinic/MySqlIntegrationTests.java
  - src/test/java/org/springframework/samples/petclinic/PostgresIntegrationTests.java
  - src/main/resources/application.properties
  - src/main/resources/application-mysql.properties
  - src/main/resources/application-postgres.properties
---

# Test profiles

Running `./mvnw -q -B test` with no active profile uses the default `database=h2`
setting in `application.properties` — an in-memory H2 database, schema/data loaded
from `db/h2/schema.sql`/`data.sql` at context startup. This is what almost all unit
and `@WebMvcTest`/`@SpringBootTest` tests run against, including
`PetClinicIntegrationTests` and the `Clinic*Tests` family.

`MySqlIntegrationTests` is different: it's annotated `@ActiveProfiles("mysql")` and
`@Testcontainers(disabledWithoutDocker = true)`, with a `@Container
@ServiceConnection MySQLContainer` field. When no Docker daemon is reachable, JUnit
**skips** (not fails) its 2 `@Test` methods (`findAll`, `ownerDetails`) — this is
why a normal local run reports `Tests run: 2, ..., Skipped: 2` for that class. With
Docker available, Testcontainers transparently starts a real `mysql:9.7` container
and wires `spring.datasource.*` to it via `@ServiceConnection` — no manual
container/URL setup needed (see the `run-full-profile-suite` skill).

`PostgresIntegrationTests` follows the same postgres-profile idea but gates
differently: a `@BeforeAll static void available()` calls
`assumeTrue(DockerClientFactory.instance().isDockerAvailable(), ...)`. A failed
JUnit 5 assumption in a `@BeforeAll` aborts the whole class before either of its 2
`@Test` methods (`findAll`, `ownerDetails`) run, which Surefire reports as
`Tests run: 0` for that class (a class-level abort, not a per-test skip) — that's
why it shows 0 rather than 2 skipped like `MySqlIntegrationTests` does. It also uses
Spring Boot's Docker Compose support directly (`spring.docker.compose.start.arguments`)
rather than a `@Testcontainers`/`@Container` field.
