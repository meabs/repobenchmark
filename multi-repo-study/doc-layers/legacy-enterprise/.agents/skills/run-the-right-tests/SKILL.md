---
name: run-the-right-tests
description: Which test class actually exercises which repository implementation in this codebase, and the exact Maven command to run them — needed before claiming any repository-layer or model change works.
---

# Running the right tests

`ClinicService`/`ClinicServiceImpl` (in `.../service/`) is tested against all three
repository implementations via three separate test classes in
`src/test/java/.../service/`, each pinning a Spring profile with `@ActiveProfiles`:

- `ClinicServiceJpaTests` → profile `jpa` → `repository/jpa/*`
- `ClinicServiceSpringDataJpaTests` → profile `spring-data-jpa` →
  `repository/springdatajpa/*`
- `ClinicServiceJdbcTests` → profile `jdbc` → `repository/jdbc/*`

All three run in the default `mvn test` — but if you're iterating on one
implementation, run the specific class to save time, e.g.:

```
JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  ./mvnw -q -B test -Dtest=ClinicServiceJdbcTests
```

**A green `ClinicServiceJpaTests` run says nothing about the JDBC or Spring Data
implementations.** For any change to a repository interface, a model's persisted
fields, or the schema, run all three before calling the work done:

```
JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" \
  ./mvnw -q -B test
```

The web/controller layer (`web/*ControllerTests`) runs against whatever profile is
active in its own test context — check the specific test class if you need to know
which one.
