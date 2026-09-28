# Answers

## 1. `GET /owners/{ownerId}`

There is no security filter, `@ControllerAdvice`, or custom `HandlerExceptionResolver` in this repo. The app-owned pieces, in order:

1. `PetClinicApplication.main` (`src/main/java/org/springframework/samples/petclinic/PetClinicApplication.java`) starts the Boot app. The request is then dispatched by Spring MVC.
2. `WebConfiguration.addInterceptors` (`src/main/java/org/springframework/samples/petclinic/system/WebConfiguration.java`, lines 56–58) has registered `localeChangeInterceptor()` (lines 45–48). `LocaleChangeInterceptor.preHandle` runs on the request. It changes the locale only when a `lang` query parameter is present. `localeResolver()` (lines 33–37) is a `SessionLocaleResolver` whose default is `Locale.ENGLISH`. That locale is what later message lookups use.
3. The mapping `@GetMapping("/owners/{ownerId}")` selects `OwnerController.showOwner` (`src/main/java/org/springframework/samples/petclinic/owner/OwnerController.java`, lines 169–177).
4. Before that handler, Spring MVC invokes the controller `@ModelAttribute` method `OwnerController.findOwner` (lines 64–70). The path variable is present, so it does not take the `ownerId == null ? new Owner()` branch. It calls `OwnerRepository.findById(Integer)` (`src/main/java/org/springframework/samples/petclinic/owner/OwnerRepository.java`, line 60).
5. `OwnerRepository` extends `JpaRepository`, so `findById` is Spring Data’s `SimpleJpaRepository.findById`. The interface javadoc (lines 50–58) says a missing row returns an empty `Optional`, and `IllegalArgumentException` is only for a null id. A numeric path id is never null. `Owner.pets` is `@OneToMany(fetch = EAGER)` (`Owner.java`, lines 64–66) and `Pet.visits` is `@OneToMany(fetch = EAGER)` (`Pet.java`, lines 56–58), so pets and visits are loaded inside that repository transaction. `spring.jpa.open-in-view=false` (`application.properties`, line 11) means the view does not keep a session open; the graph is already initialized.
6. If an owner exists, `findOwner` puts that `Owner` in the model under the name `"owner"`.
7. `OwnerController.showOwner` then runs (lines 170–177). It builds `new ModelAndView("owners/ownerDetails")` and calls `this.owners.findById(ownerId)` a second time (line 172). `mav.addObject(owner)` stores it under the name `"owner"` (Spring’s `Conventions.getVariableName` for class `Owner`).
8. Thymeleaf (`spring.thymeleaf.mode=HTML`) resolves the view name `owners/ownerDetails` to `src/main/resources/templates/owners/ownerDetails.html`. The root element `th:replace` inserts fragment `layout` from `src/main/resources/templates/fragments/layout.html` (line 3, `th:fragment="layout (template, menu)"`) with menu `"owners"`. `#{...}` keys come from `spring.messages.basename=messages/messages` (`application.properties`, line 16), i.e. `src/main/resources/messages/messages.properties` plus the locale file if one matches. The template reads `owner` fields and iterates `owner.pets` and `pet.visits`.

**Missing id.** `findOwner` (lines 67–69) does `orElseThrow` and throws `IllegalArgumentException` with the message `Owner not found with id: {ownerId}. Please ensure the ID is correct and the owner exists in the database.` That happens during model-attribute setup, so `showOwner` never runs. The similar `orElseThrow` inside `showOwner` (lines 173–174, shorter message ending in `"Please ensure the ID is correct "`) is not the one that fires for this GET.

Nothing in the repo catches that exception. Boot’s default `/error` mapping handles it. For a browser HTML request the view name is `error`, which this app supplies as `src/main/resources/templates/error.html` (the view `CrashController`’s javadoc points at; `CrashController.triggerException` is only `GET /oups` and is not on this path). The status is 500, not 404: the handler was found, then it threw. `error.html` switches on `${status}` and shows `error.500`. `application.properties` does not set `spring.web.error.include-message`, whose Boot 4 default is `never` (replacement for `server.error.include-message`), so the `IllegalArgumentException` text is not included in the error model. `CrashControllerIntegrationTests` only turns that property on (`ALWAYS`) for its own `/oups` test.

`OwnerRepository.findById` is the only repository method on this request. It runs once if the owner is missing (inside `findOwner`) and twice if the owner exists (`findOwner`, then `showOwner`).

## 2. The id-mismatch check in `processUpdateOwnerForm`

Under a normal form submit, no. The `if` at `OwnerController.java` lines 152–156 does not run. Its result is fixed by two methods:

1. `OwnerController.findOwner` (lines 64–70). On `POST /owners/{ownerId}/edit` this `@ModelAttribute("owner")` method runs first and loads the row with `owners.findById(ownerId)`. The handler argument `Owner owner` is that same model attribute (the parameter name is `owner`). So `owner.getId()` is the path id. If no row exists, `findOwner` throws and `processUpdateOwnerForm` is never entered.
2. `OwnerController.setAllowedFields` (lines 59–62). `@InitBinder` calls `dataBinder.setDisallowedFields("id", "*.id")`. Request parameters cannot overwrite `id` while Spring binds the form onto that owner.

The edit form (`src/main/resources/templates/owners/createOrUpdateOwnerForm.html`, lines 8–15) only posts `firstName`, `lastName`, `address`, `city`, and `telephone`. It has no id input. A tampered `id` parameter would still be dropped by `setAllowedFields`. After binding, `owner.getId()` and the path `ownerId` are the same value, so `Objects.equals` is true and the reject branch is skipped. `owner.setId(ownerId)` on line 158 runs only after that check; it does not decide the check.

The check can be forced in a test, not by the form. `OwnerControllerTests.processUpdateOwnerFormWithIdMismatch` stubs `findById(1)` to return an `Owner` whose id is 2 and posts `flashAttr("owner", owner)`. That is not a normal form submission.

## 3. Is the `vets` cache missing an eviction policy a bug?

No. `VetRepository` (`src/main/java/org/springframework/samples/petclinic/vet/VetRepository.java`) extends `Repository<Vet, Integer>`, not `CrudRepository` or `JpaRepository`, so Spring Data does not add `save`, `delete`, or any other method. The interface declares exactly two methods, and both are the cached reads:

- `Collection<Vet> findAll()` (lines 44–46), `@Cacheable("vets")`
- `Page<Vet> findAll(Pageable)` (lines 54–56), `@Cacheable("vets")`

There is no `@CacheEvict` anywhere in the repo. `CacheConfiguration.cacheConfiguration` (lines 49–51) only calls `setStatisticsEnabled(true)` on a `MutableConfiguration`. Callers (`VetController.showVetList` / `findPaginated` and `VetController.showResourcesVetList`) only read. Nothing in this application writes a `Vet` through this repository, so there is no update that an eviction policy would have to observe. The cache stays valid for the process lifetime. It would go stale only if something outside this repository changed the `vets` table. This app never does that.

## 4. Adding `@Column private String someField` to `Owner` and saving

The app starts. Hibernate does not add a column. The save fails when the `Owner` is flushed.

`src/main/resources/application.properties` line 10 sets `spring.jpa.hibernate.ddl-auto=none`. With that value Hibernate neither creates nor validates the schema from the entity. Tables come from `spring.sql.init.schema-locations=classpath*:db/${database}/schema.sql` (line 3), and the default `database=h2` (line 2) loads `src/main/resources/db/h2/schema.sql`. The `owners` table there (lines 36–43) has only `id`, `first_name`, `last_name`, `address`, `city`, and `telephone`. MySQL (`db/mysql/schema.sql`, lines 28–36) and Postgres (`db/postgres/schema.sql`, lines 26–33) are the same set of columns.

`someField` is still a mapped column. Line 12 sets `spring.jpa.hibernate.naming.physical-strategy=org.hibernate.boot.model.naming.PhysicalNamingStrategySnakeCaseImpl`, so the column name in SQL is `some_field`. `OwnerRepository.save` (used by `OwnerController.processCreationForm` line 84 and `processUpdateOwnerForm` line 159) flushes an INSERT or UPDATE that references `some_field`. The database rejects the statement because that column is not in `owners` (H2 reports a column-not-found / bad-SQL-grammar error). Spring wraps that as a data-access exception. The controller does not catch it, so the request becomes the same 500 `error.html` path as other uncaught exceptions. The value never persists. This happens for any flush of `Owner`, including when `someField` is null, because dynamic insert/update is not enabled; the populated value is not what makes the SQL invalid.

`ddl-auto=none` is not `validate`, so startup and the existing `data.sql` inserts still succeed. A nullable `@Column String` does not require `data.sql` changes.

To make the field persist, add a nullable `some_field` column to `owners` in:

- `src/main/resources/db/h2/schema.sql` (default profile and local run)
- `src/main/resources/db/mysql/schema.sql`
- `src/main/resources/db/postgres/schema.sql`

## 5. Why `./mvnw test` typically reports 2 skipped tests

The two skips are `MySqlIntegrationTests.findAll` and `MySqlIntegrationTests.ownerDetails` in `src/test/java/org/springframework/samples/petclinic/MySqlIntegrationTests.java`. The class annotation responsible is `@Testcontainers(disabledWithoutDocker = true)` (line 43).

With no Docker daemon, Testcontainers disables those two `@Test` methods instead of failing them. Surefire’s message is `disabledWithoutDocker is true and Docker is not available`. Confirmed here with Docker down: that class reported `Tests run: 2, Skipped: 2`.

`PostgresIntegrationTests` also has two `@Test` methods (`findAll`, `ownerDetails`), but they are not part of that skip count. Its `@BeforeAll` method `available()` (lines 66–68) calls `Assumptions.assumeTrue(DockerClientFactory.instance().isDockerAvailable(), ...)`. A failed assumption there aborts the class before either test is counted. Surefire reported `Tests run: 0, Skipped: 0` for that class. That gate is `assumeTrue`, not an annotation.

`@DisabledInNativeImage` and `@DisabledInAotMode` on several test classes do not skip a normal JVM `./mvnw test`. They apply only in a GraalVM native image or AOT test run. No other test in this repo is disabled on a default run, so the suite total is 2 skipped, both from `MySqlIntegrationTests`.
