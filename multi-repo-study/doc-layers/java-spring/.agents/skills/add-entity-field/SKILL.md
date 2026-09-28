---
name: add-entity-field
description: Add a field to an existing JPA entity in this repo (Owner, Pet, Vet, Visit, PetType) — including the SQL schema edits this repo requires, since Hibernate does not auto-generate DDL here.
---

# Add a field to an existing entity

1. Add the field + `@Column` (and any `jakarta.validation.constraints.*` annotation)
   to the entity class under `src/main/java/org/springframework/samples/petclinic/`
   (e.g. `owner/Owner.java`, `owner/Pet.java`, `vet/Vet.java`, `owner/Visit.java`),
   plus a getter/setter, matching the style already used by sibling fields in that
   class (see `Owner.address`/`Owner.city` for a plain `@NotBlank` string field).
2. **This repo does not auto-generate schema from entities**:
   `application.properties` sets `spring.jpa.hibernate.ddl-auto=none`. The schema
   comes from `src/main/resources/db/<database>/schema.sql`, loaded at startup via
   `spring.sql.init.schema-locations`. You must add the column there yourself, for
   **all three** database profiles that ship schema/data files:
   `db/h2/schema.sql` (used by the default test profile and local dev),
   `db/mysql/schema.sql`, `db/postgres/schema.sql`. If existing seed rows need a
   value for the new column, also update the matching `data.sql` in each of those
   three directories — H2 in particular will reject inserts that don't match a
   `NOT NULL` column you added without a default.
3. If the field participates in the create/edit form, add it to the relevant
   Thymeleaf template under `src/main/resources/templates/` (see
   `pets/createOrUpdatePetForm.html` or `owners/createOrUpdateOwnerForm.html` for the
   existing `th:field` binding pattern) — skip this if the field is
   read-only/system-managed.
4. Add or extend a test in the matching `src/test/java/.../owner/OwnerTests.java` /
   `PetTests` style unit test (entity-level) and, if it's exercised through a
   controller, the relevant `*ControllerTests` (uses `@WebMvcTest` + Mockito, not a
   real DB — see `OwnerControllerTests.java` for the pattern).
5. Run `./mvnw -q -B test` (see `run-full-profile-suite` skill if you need to also
   exercise the mysql/postgres profiles) before calling this done.
