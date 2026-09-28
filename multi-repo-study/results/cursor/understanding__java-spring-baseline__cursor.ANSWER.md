# Answers

## 1. `GET /owners/{ownerId}`

There is no project-level filter or `@ControllerAdvice`. A normal hit (owner row exists) goes through the pieces below, in order.

1. Embedded Tomcat hands the request to Spring MVC's `DispatcherServlet` (auto-configured by `spring-boot-starter-webmvc`; not a source file in this repo).
2. `WebConfiguration.addInterceptors` (`src/main/java/org/springframework/samples/petclinic/system/WebConfiguration.java`) has registered the `LocaleChangeInterceptor` bean from `WebConfiguration.localeChangeInterceptor`. Its `preHandle` runs on every request. With no `lang` query parameter it does not change the locale.
3. `RequestMappingHandlerMapping` selects `OwnerController.showOwner`, the `@GetMapping("/owners/{ownerId}")` method at `OwnerController.java` lines 169–177.
4. Before that method body runs, Spring's `ModelFactory` invokes every `@ModelAttribute` method on the controller. That is `OwnerController.findOwner` (lines 64–70). The mapping has an `ownerId` path variable, so the `Integer ownerId` argument is non-null and `findOwner` does not take the `new Owner()` branch.
5. `findOwner` calls `OwnerRepository.findById(Integer)` (`src/main/java/org/springframework/samples/petclinic/owner/OwnerRepository.java` line 60). The interface extends `JpaRepository`, so the call is implemented by Spring Data's `SimpleJpaRepository.findById`, which loads the row with `EntityManager.find`. `Owner.pets` is `FetchType.EAGER` (`Owner.java` line 64) and `Pet.visits` is `FetchType.EAGER` (`Pet.java` line 56), so that same persistence call also selects pets, types, and visits. `spring.jpa.open-in-view=false` (`application.properties` line 11) does not matter for the page, because those associations are already initialized when the repository transaction ends.
6. The `Owner` is placed in the model under the name `"owner"`.
7. `OwnerController.showOwner` runs (lines 170–177). It builds `new ModelAndView("owners/ownerDetails")`, then calls `OwnerRepository.findById` a second time (line 172) and `mav.addObject(owner)`. `addObject` uses the decapitalized class name `"owner"`, so this second instance replaces the one `findOwner` put in the model. A full-app test of `GET /owners/1` logs that owner `SELECT` twice, once per call.
8. The view name `owners/ownerDetails` is resolved by Boot's `ThymeleafViewResolver` (`spring.thymeleaf.mode=HTML`) to `src/main/resources/templates/owners/ownerDetails.html`, which pulls in `src/main/resources/templates/fragments/layout.html`.

`OwnerController.setAllowedFields` is not on this path. `showOwner` only takes a `@PathVariable`, so no `WebDataBinder` is created.

If no owner has that id, the failure is in step 5, not in `showOwner`. `findOwner` line 68 does `orElseThrow` and throws `IllegalArgumentException` with the message `"Owner not found with id: " + ownerId + ". Please ensure the ID is correct and the owner exists in the database."` `showOwner` is never entered. Its own `orElseThrow` (lines 173–174) is only reachable if the row disappears between the two `findById` calls.

Nothing in this repo handles that exception (`CrashController.triggerException` only serves `GET /oups`). `IllegalArgumentException` has no `@ResponseStatus` and is not one of the exceptions Spring MVC's `DefaultHandlerExceptionResolver` turns into a 4xx, so the container error dispatch is status 500. `org.springframework.boot.webmvc.autoconfigure.error.BasicErrorController` renders the view name `error`, which is `src/main/resources/templates/error.html`. That template's `th:switch="${status}"` takes the `500` branch.

## 2. Can the id-mismatch check fire on a normal submit?

No. On a normal `POST /owners/{ownerId}/edit` from the edit form, `owner.getId()` and the path `ownerId` are the same value, so `if (!Objects.equals(owner.getId(), ownerId))` (`OwnerController.java` lines 152–156) does not reject. Two methods, both on `OwnerController`, make that outcome fixed before the `if` runs.

1. `setAllowedFields` (lines 59–62), the `@InitBinder` method, calls `dataBinder.setDisallowedFields("id", "*.id")`. A request parameter named `id` is not written onto the `Owner`. The form that actually posts, `src/main/resources/templates/owners/createOrUpdateOwnerForm.html`, has no id input anyway: only `firstName`, `lastName`, `address`, `city`, and `telephone`.
2. `findOwner` (lines 64–70) runs first, as `@ModelAttribute("owner")`. For this mapping `ownerId` is present, so it loads that owner with `OwnerRepository.findById(ownerId)`. The handler argument `Owner owner` on `processUpdateOwnerForm` is that same model attribute (the parameter name is `owner`). The instance already has the path id from the database. Binding then copies the posted name/address fields onto it and cannot replace `id`.

`owner.setId(ownerId)` on line 158 runs only after the check, and it stores the same id again.

The branch is reachable only when the model already contains an `"owner"` whose id is not the path id, which makes Spring skip `findOwner`. `OwnerControllerTests.processUpdateOwnerFormWithIdMismatch` does that with `flashAttr("owner", owner)`: the flashed owner has id 2 and the path id is 1. That is not a normal form post.

## 3. Is the `vets` cache missing an eviction policy a bug?

No. `VetRepository` (`src/main/java/org/springframework/samples/petclinic/vet/VetRepository.java`) extends `Repository<Vet, Integer>`, not `CrudRepository` or `JpaRepository`, so Spring Data exposes only the methods declared on the interface. Those are exactly two, and both are reads:

- `Collection<Vet> findAll()` (lines 44–46), `@Transactional(readOnly = true)` and `@Cacheable("vets")`
- `Page<Vet> findAll(Pageable)` (lines 54–56), same annotations

There is no `save`, `delete`, or `findById`. `VetController` only calls those two `findAll` overloads. Vet rows are inserted by the SQL seed scripts (`data.sql`), not by the application. `CacheConfiguration.cacheConfiguration` builds a `MutableConfiguration` and only calls `setStatisticsEnabled(true)` (lines 49–51); the JCache default is no expiry. Nothing in this repository can change a vet after the cache is filled, so there is no write that an eviction policy would have to observe.

## 4. Adding `someField` to `Owner` and saving it

The application starts. The save fails, and the value is not stored.

`src/main/resources/application.properties` line 10 sets `spring.jpa.hibernate.ddl-auto=none`. Hibernate will not create or alter tables, and it does not validate the schema at startup. The tables come from `spring.sql.init.schema-locations=classpath*:db/${database}/schema.sql` with `database=h2` (lines 2–3). `CREATE TABLE owners` in `src/main/resources/db/h2/schema.sql` (lines 36–43) has no column for the new field.

Line 12 sets `spring.jpa.hibernate.naming.physical-strategy` to `org.hibernate.boot.model.naming.PhysicalNamingStrategySnakeCaseImpl`, so `@Column private String someField` is mapped to `some_field`. H2 folds unquoted identifiers to upper case, so the SQL refers to `SOME_FIELD`. On `OwnerRepository.save` (inherited from `JpaRepository`; called from `OwnerController.processCreationForm` and `processUpdateOwnerForm`), Hibernate includes that column in the `INSERT` or `UPDATE`. The column is not in `owners`, so the database rejects the statement. Spring's persistence exception translation surfaces that as a `DataAccessException` (an `InvalidDataAccessResourceUsageException` around Hibernate's `SQLGrammarException` / H2's `JdbcSQLSyntaxErrorException`). The transaction rolls back.

To make the column real, add it to the script that creates the table:

- `src/main/resources/db/h2/schema.sql` for the default profile
- `src/main/resources/db/mysql/schema.sql` and `src/main/resources/db/postgres/schema.sql` if those profiles should persist it too

H2 `data.sql` and MySQL `data.sql` insert owners with positional `INSERT INTO owners VALUES (...)`. After the column is added, those statements must list a value for it or startup seed loading fails. Postgres `data.sql` names its columns (`first_name, last_name, address, city, telephone`), so a nullable `some_field` does not require a change there.

## 5. Why `./mvnw test` reports 2 skipped tests

The two skips are `MySqlIntegrationTests.findAll` and `MySqlIntegrationTests.ownerDetails` in `src/test/java/org/springframework/samples/petclinic/MySqlIntegrationTests.java`. The class is annotated `@Testcontainers(disabledWithoutDocker = true)` (line 43). When no Docker daemon is listening, the Testcontainers JUnit extension disables both tests before they run. Surefire records each as skipped with the message `disabledWithoutDocker is true and Docker is not available`.

A default run on this machine (no Docker) printed `Tests run: 74, Failures: 0, Errors: 0, Skipped: 2`. `@DisabledInNativeImage` and `@DisabledInAotMode` do not skip that run; they only apply in a GraalVM native image or AOT test mode.

`PostgresIntegrationTests` also bails out without Docker, but not via an annotation and not as those two skips. Its `@BeforeAll` method `available` calls `Assumptions.assumeTrue(DockerClientFactory.instance().isDockerAvailable(), ...)`. With Docker down, Surefire reports that class as `Tests run: 0, Skipped: 0`, so it does not add to the skipped total.
