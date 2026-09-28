---
name: add-model-field
description: Add a field to a domain entity (Owner, Pet, Vet, Visit, PetType) in this repo — this codebase has 3 parallel repository implementations behind one interface, and a new column needs different amounts of work in each. Use for any schema/model change, not just additions.
---

# Add a field to a domain entity

This repo's `repository` interfaces (`OwnerRepository`, `PetRepository`,
`VetRepository`, `VisitRepository`, all directly under `.../repository/`) each have
**three** implementations, chosen at runtime by a Spring profile (see
`okf/repositories/index.md` for which one is actually active by default — it is not
`spring-data-jpa`). A field change touches them unevenly:

1. **Model**: add the field to the entity class in `.../model/` with the matching
   `@Column(name = "...")` annotation (JPA-style annotations are present on every
   model class regardless of which repository profile ends up reading it).
2. **`repository/jpa/Jpa<X>RepositoryImpl.java`** and
   **`repository/springdatajpa/SpringData<X>Repository.java`**: usually need
   **zero** changes for a plain new column — Hibernate maps it automatically off the
   entity's `@Column` annotation. Only touch these if the new field needs a custom
   query.
3. **`repository/jdbc/Jdbc<X>RepositoryImpl.java`**: **always** needs manual changes
   — this implementation hand-writes SQL as `JdbcClient` text blocks (`SELECT`
   column lists and `UPDATE ... SET` clauses). Add the new column to every SQL
   string that reads or writes the entity. Missing one is the single most common way
   this kind of change breaks silently in the JDBC profile only.
4. **Schema**: add the column to `src/main/resources/db/h2/schema.sql` at minimum
   (what the test suite runs against). The `hsqldb/`, `mysql/`, and `postgresql/`
   sibling directories hold the same table for their respective dialects — update
   them too if you want the change to be real for every supported database, not
   just the one tests happen to use.
5. If the field should be user-editable, also update the relevant JSP form under
   `src/main/webapp/WEB-INF/jsp/` (see `add-controller-page` skill) — a model/schema
   change alone doesn't reach the UI.

See `run-the-right-tests` before calling this done: passing `ClinicServiceJpaTests`
alone does not tell you the JDBC implementation still works.
