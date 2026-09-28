---
type: concept
title: Owner / Pet / Visit aggregate
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:39:22Z
sources:
  - src/main/java/org/springframework/samples/petclinic/owner/Owner.java
  - src/main/java/org/springframework/samples/petclinic/owner/Pet.java
  - src/main/java/org/springframework/samples/petclinic/owner/Visit.java
  - src/main/java/org/springframework/samples/petclinic/model/BaseEntity.java
  - src/main/resources/db/h2/schema.sql
---

# Owner / Pet / Visit aggregate

`Owner` (table `owners`) extends `Person` (first/last name) and adds
`address`/`city`/`telephone` (all `@NotBlank`; `telephone` also `@Pattern(\d{10})`).
It owns a `List<Pet>` via `@OneToMany(cascade = ALL, fetch = EAGER)` on a
`@JoinColumn(name = "owner_id")` — i.e. the foreign key lives on the `pets` table,
not a join table, and pets are always eagerly loaded with their owner (see
`schema.sql`: `pets.owner_id` FK plus a `unique_owner_pet_name` unique constraint on
`(owner_id, name)` — this is what backs the duplicate-pet-name rejection in
`PetController`, enforced at both the Java layer and the DB layer).

`Pet` extends `NamedEntity` (adds `name`), has a `birthDate`, a `@ManyToOne PetType`,
and a `Set<Visit>` (also cascade-all, eager, FK on `visits.pet_id`).

All three (`Owner`, `Pet`, and transitively `Visit`/`Vet`) extend `BaseEntity`, which
supplies the `@Id @GeneratedValue(IDENTITY) Integer id` and an `isNew()` helper
(`id == null`) — used throughout the controllers to distinguish create vs. update
flows (e.g. `Owner.addPet` dedupes by id only for non-new pets).

**Schema is not Hibernate-generated.** `application.properties` sets
`spring.jpa.hibernate.ddl-auto=none`; the actual table definitions live in
`src/main/resources/db/<h2|mysql|postgres>/schema.sql`, loaded at startup via
`spring.sql.init.schema-locations`. Any new column on these entities needs a
matching edit in all three `schema.sql` files (see the `add-entity-field` skill) —
adding a JPA field/annotation alone does nothing to the database.
