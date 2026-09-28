---
name: add-repository-query
description: Add a new lookup/query method to a Spring Data JPA repository in this repo (OwnerRepository, VetRepository, PetTypeRepository) — the derived-query-method convention this codebase relies on, and when to fall back to @Query.
---

# Add a repository query method

1. Repositories live in the entity's package (`owner/OwnerRepository.java`,
   `vet/VetRepository.java`, `owner/PetTypeRepository.java`), each a plain interface
   extending `JpaRepository<Entity, Integer>` — no implementation class, no custom
   `@Repository` bean.
2. Prefer a **derived query method** (Spring Data parses the method name into a
   query) over `@Query`, matching the existing style — see
   `OwnerRepository.findByLastNameStartingWith(String lastName, Pageable pageable)`.
   Method name conventions: `findBy<Property>`, `findBy<Property>StartingWith`,
   `findBy<Property>ContainingIgnoreCase`, etc. Only reach for `@Query` when the
   derived name would be unreadable or the query needs a join/aggregation the
   naming convention can't express.
3. If the result can be large (anything not looked up by a single id), take a
   `Pageable` parameter and return `Page<Entity>` — see `findByLastNameStartingWith`
   — rather than a raw `List`, to match how `OwnerController`/`VetController`
   already paginate at page size 5.
4. Javadoc the new method in the same style as the existing methods in that
   interface (params, return semantics for the not-found case).
5. Add a test exercising the new method. Repository-level tests in this repo run
   against the real H2-backed Spring context (see `ClinicServiceTests` /
   `ClinicServiceJdbcTests` for the pattern) rather than mocking the repository —
   follow that pattern, don't introduce a mock-based test for this layer.
6. Run `./mvnw -q -B test`.
