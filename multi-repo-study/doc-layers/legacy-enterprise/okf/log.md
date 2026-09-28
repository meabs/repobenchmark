---
type: log
title: Build log
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
---

# Build log

- 2026-09-28: Bundle built by reading `business-config.xml`,
  `PetclinicInitializer.java`, the 3 `ClinicService*Tests` classes, one
  representative repository implementation per package (`JdbcOwnerRepositoryImpl`),
  the domain model classes, `OwnerController`, and `db/h2/schema.sql`. The
  default-active-profile finding (`jpa`, set in `PetclinicInitializer`) was
  cross-checked against the `<beans profile="...">` wiring in
  `business-config.xml` to confirm the `jpa` profile really does select
  `repository/jpa/*` and not one of the other two — both sources agree.
