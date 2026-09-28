---
type: concept
title: Domain model
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - src/main/java/org/springframework/samples/petclinic/model/Owner.java
  - src/main/java/org/springframework/samples/petclinic/model/Pet.java
  - src/main/java/org/springframework/samples/petclinic/model/Vet.java
  - src/main/java/org/springframework/samples/petclinic/model/Visit.java
  - src/main/java/org/springframework/samples/petclinic/model/PetType.java
  - src/main/java/org/springframework/samples/petclinic/model/Person.java
  - src/main/java/org/springframework/samples/petclinic/model/BaseEntity.java
  - src/main/resources/db/h2/schema.sql
---

# Domain model

`BaseEntity` (id) → `NamedEntity` (+ name, used by `PetType`/`Specialty`) and
`Person` (first/last name, used by `Owner`/`Vet`). `Owner` extends `Person` and adds
`address`, `city`, `telephone`, plus a `@OneToMany(cascade = CascadeType.ALL,
mappedBy = "owner") Set<Pet> pets`. `Pet` has a `PetType` and belongs to an `Owner`;
`Visit` belongs to a `Pet`.

Every entity carries JPA annotations (`@Entity`, `@Column`, etc.) regardless of
which repository profile ends up reading it (see `../repositories/index.md`) —
`jpa` and `spring-data-jpa` read these directly via Hibernate; `jdbc` ignores them
entirely and maps columns by hand in `repository/jdbc/*`.

Schema source of truth for the profile the test suite actually runs against is
`src/main/resources/db/h2/schema.sql` — the `hsqldb/`, `mysql/`, and `postgresql/`
siblings hold the same tables for their respective dialects and must be kept in
sync by hand; there is no shared migration tool across them (no Flyway/Liquibase in
this repo, unlike some other Spring PetClinic variants).
