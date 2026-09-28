---
name: run-full-profile-suite
description: Run this repo's tests including the mysql/postgres Testcontainers-gated integration tests, not just the default H2-profile suite that `./mvnw test` exercises on its own.
---

# Run the full (Docker-gated) test suite

`./mvnw -q -B test` alone runs every test **except** the two `@Test` methods in
`MySqlIntegrationTests` (`findAll`, `ownerDetails`) — they carry
`@Testcontainers(disabledWithoutDocker = true)` and are silently skipped, not
failed, when no Docker daemon is reachable. `PostgresIntegrationTests` similarly
spins up a Testcontainers-managed Postgres, but its class currently has 0 `@Test`
methods, so it contributes nothing either way.

To actually exercise the mysql-profile path:

1. Make sure a Docker daemon is running and reachable (`docker info` succeeds).
2. Run `./mvnw -q -B test` as normal — Testcontainers will detect Docker and pull/run
   a real `mysql:9.7` container itself; no manual container setup needed.
3. Check the surefire report for `MySqlIntegrationTests` specifically
   (`target/surefire-reports/org.springframework.samples.petclinic.MySqlIntegrationTests.txt`)
   to confirm `Tests run: 2, Skipped: 0` rather than `Skipped: 2`.

Don't try to fake this by hand-starting a MySQL container and pointing
`spring.datasource.url` at it — the test class's `@Container`/`@ServiceConnection`
wiring manages its own container lifecycle and will ignore a manually-started one.
If Docker genuinely isn't available in your environment, the 2 skips on the default
run are expected and not a failure signal.
