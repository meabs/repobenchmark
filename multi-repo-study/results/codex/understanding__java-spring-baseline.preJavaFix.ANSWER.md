# Answers

## 1. `GET /owners/{ownerId}`

1. Spring MVC selects `OwnerController.showOwner` in `src/main/java/org/springframework/samples/petclinic/owner/OwnerController.java:169-176` because of `@GetMapping("/owners/{ownerId}")`.
2. Before the handler method runs, the controller's `@ModelAttribute("owner")` method `OwnerController.findOwner` (lines 64-70) resolves the path variable. Because `ownerId` is non-null, it calls `OwnerRepository.findById(Integer)`.
3. `OwnerRepository` is `src/main/java/org/springframework/samples/petclinic/owner/OwnerRepository.java`. Its declared `findById(Integer)` (line 60) is implemented by the Spring Data JPA repository proxy inherited through `JpaRepository`; it loads the `Owner` entity (mapped by `Owner.java`, with inherited fields from `Person.java` and `BaseEntity.java`). `findOwner` returns that entity as the model attribute named `owner`.
4. `showOwner(int ownerId)` then calls `this.owners.findById(ownerId)` a second time (line 172), unwraps the `Optional` at lines 173-174, adds the owner with `mav.addObject(owner)` (line 175), and returns the view name `owners/ownerDetails`.
5. Thymeleaf resolves that view to `src/main/resources/templates/owners/ownerDetails.html`, which renders the `owner` model object and its pets/visits (and uses the layout fragment).

If no owner exists, the first lookup in `findOwner` returns `Optional.empty()`, so its `orElseThrow` raises `IllegalArgumentException` with the “Owner not found with id” message before `showOwner` is entered; the normal owner-details view is not rendered. `showOwner` has a second equivalent `orElseThrow` for the same missing-owner case if execution ever reaches that method without the model-attribute lookup.

## 2. Owner ID mismatch check

Under normal submission, the check in `OwnerController.processUpdateOwnerForm` (lines 145-161) is effectively predetermined to be false. Two controller methods cause that:

1. `OwnerController.findOwner` (lines 64-70), the `@ModelAttribute("owner")` method, loads the existing owner using the URL's `ownerId`, so the bound `Owner` starts with that same database ID.
2. `OwnerController.setAllowedFields` (lines 59-62) calls `dataBinder.setDisallowedFields("id", "*.id")`. Form binding therefore cannot overwrite the ID from request parameters; the form template also does not post an ID.

Consequently `owner.getId()` remains the ID loaded for the path, which equals the `int ownerId` argument. The mismatch branch is still testable with an externally supplied model state: `OwnerControllerTests.processUpdateOwnerFormWithIdMismatch` flashes an owner whose ID differs from the path ID.

## 3. `vets` cache and eviction

It is not a stale-cache bug within this codebase. `src/main/java/org/springframework/samples/petclinic/vet/VetRepository.java` extends the bare `Repository` interface and exposes only:

- `findAll()` returning `Collection<Vet>` (line 46), and
- `findAll(Pageable)` returning `Page<Vet>` (line 56).

There is no `save`, update, delete, or other mutation method on `VetRepository`, and no application code mutates vets through another vet repository method. Thus no in-application write can make either cached result stale. `CacheConfiguration` creates the `vets` cache and enables caching, but its lack of eviction is harmless for this read-only repository. External database changes would still require an eviction/expiration strategy if they are in scope.

## 4. Adding `someField` to `Owner`

With `@Column private String someField;` and its getter/setter added to `Owner.java`, Hibernate will include the mapped property in generated `INSERT`/`UPDATE` SQL. However, `src/main/resources/application.properties:10` sets:

```properties
spring.jpa.hibernate.ddl-auto=none
```

So Hibernate does not alter or validate the existing schema. The SQL initialization schemas still create `owners` without that column. The application can start, but saving an owner with a populated field fails when the database executes SQL referring to the missing physical column (normally an unknown-column/column-not-found SQL exception, with the transaction rolled back).

To persist the field, the entity change must be accompanied by `some_field` in the `owners` table definition in the applicable schema file(s):

- `src/main/resources/db/h2/schema.sql`
- `src/main/resources/db/mysql/schema.sql`
- `src/main/resources/db/postgres/schema.sql`

The physical naming strategy in `application.properties:12` maps `someField` to `some_field`. For an already-created MySQL or PostgreSQL database, an actual `ALTER TABLE` migration (or table recreation) is also required; changing a `CREATE TABLE IF NOT EXISTS` script does not modify an existing table. Alternatively, changing `spring.jpa.hibernate.ddl-auto` to a schema-updating mode would change startup behavior, but the current configuration deliberately does not do that.

## 5. Two skipped tests

The two skipped tests are the two `@Test` methods in `src/test/java/org/springframework/samples/petclinic/MySqlIntegrationTests.java` (`findAll` and `ownerDetails`). The class is annotated at line 43 with:

```java
@Testcontainers(disabledWithoutDocker = true)
```

When Docker is unavailable, the Testcontainers JUnit extension disables the class, so both methods are reported as skipped rather than executed. The other class, `PostgresIntegrationTests`, has a separate `@BeforeAll available()` assumption (`assumeTrue(DockerClientFactory.instance().isDockerAvailable(), ...)`) and can add two more skipped tests in an environment where Docker is entirely unavailable; therefore the exact total is environment-dependent. The expected “2 skipped” result refers to the MySQL Testcontainers gate.
