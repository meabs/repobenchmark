# Answers

## 1. `GET /owners/{ownerId}`

1. Spring MVC matches the request to `OwnerController.showOwner` in `src/main/java/org/springframework/samples/petclinic/owner/OwnerController.java:169-177`, because it is annotated `@GetMapping("/owners/{ownerId}")`.
2. Before the handler runs, the controller-level `@ModelAttribute("owner")` method `OwnerController.findOwner` (`OwnerController.java:64-70`) runs. Its `ownerId` path variable is non-null, so it calls `OwnerRepository.findById(ownerId)` (`src/main/java/org/springframework/samples/petclinic/owner/OwnerRepository.java:60`). Spring Data supplies the repository implementation through the `JpaRepository<Owner, Integer>` base interface. The returned owner is added to the model under `owner`.
3. `showOwner` then creates `new ModelAndView("owners/ownerDetails")` (`OwnerController.java:171`) and calls `owners.findById(ownerId)` again (`OwnerController.java:172`). It unwraps the `Optional` with `orElseThrow` (`OwnerController.java:173-174`), adds the resulting owner with `mav.addObject(owner)` (`OwnerController.java:175`), and returns the `ModelAndView`.
4. Thymeleaf renders `src/main/resources/templates/owners/ownerDetails.html`, whose root uses the `fragments/layout` fragment from `src/main/resources/templates/fragments/layout.html`; the page reads the `owner` and its pets/visits.

If the first `findById` returns `Optional.empty()`, `findOwner` throws `IllegalArgumentException` before `showOwner` runs. If the owner disappears between the two lookups, the second `orElseThrow` does the same. There is no controller-level 404 conversion; the exception goes through Spring Boot's default error handling and the error view is `src/main/resources/templates/error.html` (normally a 500 response for this unhandled exception).

## 2. Owner ID mismatch check

No, not during a normal form submission. Two separate methods make the value effectively predetermined:

- `OwnerController.findOwner` (`OwnerController.java:64-70`) runs as the `@ModelAttribute("owner")` method for the edit request and loads the owner by the URL's `ownerId`, so the bound `Owner` already has that persisted ID.
- `OwnerController.setAllowedFields` (`OwnerController.java:59-62`) calls `dataBinder.setDisallowedFields("id", "*.id")`. Therefore an `id` supplied in the form body is ignored and cannot replace the ID obtained from the path lookup.

Consequently, once validation passes, `processUpdateOwnerForm` (`OwnerController.java:145-162`) compares the path ID with the same ID that `findOwner` loaded, so its `Objects.equals` check at lines 152-156 cannot normally reject the submission.

## 3. `VetRepository` cache

It is not a bug in this codebase's current repository API. `VetRepository` (`src/main/java/org/springframework/samples/petclinic/vet/VetRepository.java`) extends the narrow `Repository<Vet, Integer>` interface and exposes only:

- `findAll()` returning `Collection<Vet>` (lines 44-46)
- `findAll(Pageable pageable)` returning `Page<Vet>` (lines 54-56)

It exposes no `save`, `delete`, or other mutation method that would require eviction. `CacheConfiguration` only creates the `vets` cache (lines 31-38) and enables statistics; with no in-code write path for vets, no eviction policy is needed to keep this repository's reads coherent. The cache could still become stale if vets are changed outside this API (for example, directly in the database), but that is an external-consistency limitation, not a missing eviction for a repository method that exists here.

## 4. Adding `someField` to `Owner`

The application can start, but the field is not magically added to the database. `src/main/resources/application.properties:10` sets:

```properties
spring.jpa.hibernate.ddl-auto=none
```

Hibernate therefore does not create or alter the schema for the new mapping. With the naming strategy configured at `application.properties:12`, the field maps to the `some_field` column. A save whose SQL touches the owner row will reference that column, but the existing `owners` table has no such column, so the database rejects the SQL (the exception is propagated/wrapped as a persistence or SQL grammar/data-access failure and the save does not persist). Reads of `Owner` can also fail for the same reason because Hibernate includes mapped columns in its select.

To persist it, keep the JPA field/getter/setter in `src/main/java/org/springframework/samples/petclinic/owner/Owner.java` and add the matching `some_field` column to the `owners` table definition in all three schema files:

- `src/main/resources/db/h2/schema.sql`
- `src/main/resources/db/mysql/schema.sql`
- `src/main/resources/db/postgres/schema.sql`

The active schema is selected through `spring.sql.init.schema-locations=classpath*:db/${database}/schema.sql` in `application.properties`, with the profile-specific `database` value selecting the relevant one.

## 5. Why two tests are skipped

The class is `src/test/java/org/springframework/samples/petclinic/MySqlIntegrationTests.java`. It has two `@Test` methods, `findAll` and `ownerDetails` (lines 61-72), and the class annotation at line 43 is:

```java
@Testcontainers(disabledWithoutDocker = true)
```

When Docker is unavailable, Testcontainers skips those two MySQL-container tests instead of failing them, so the default `./mvnw test` commonly reports `Skipped: 2`.
