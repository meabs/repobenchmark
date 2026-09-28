# Answers

## 1. `GET /owners/{ownerId}`

1. Spring MVC matches the request to `OwnerController.showOwner` in
   `src/main/java/org/springframework/samples/petclinic/owner/OwnerController.java:169-177`
   (`@GetMapping("/owners/{ownerId}")`). There is no service layer between the
   controller and repository.
2. Before the handler method runs, the controller's `@ModelAttribute("owner")`
   method, `OwnerController.findOwner` (lines 64-70), resolves the same path
   variable and calls `OwnerRepository.findById(ownerId)` (line 67). The repository
   redeclares that method at
   `src/main/java/org/springframework/samples/petclinic/owner/OwnerRepository.java:60`;
   its implementation is the Spring Data JPA repository proxy supplied because the
   interface extends `JpaRepository<Owner, Integer>` at line 36.
3. If that lookup succeeds, `findOwner` returns the managed `Owner` as the
   `owner` model attribute. `Owner` is defined in `Owner.java`; its `@OneToMany`
   `pets` association (lines 64-67) is eager, so the owner view has its pets
   available.
4. `showOwner` then constructs `new ModelAndView("owners/ownerDetails")` (line
   171), calls `OwnerRepository.findById(ownerId)` a second time (line 172),
   unwraps it with `orElseThrow` (lines 173-174), and calls
   `ModelAndView.addObject(owner)` (line 175). It returns that `ModelAndView`.
5. The view name resolves to
   `src/main/resources/templates/owners/ownerDetails.html`. Its root `th:replace`
   includes `templates/fragments/layout.html`; the page evaluates the owner's
   `getFirstName`, `getLastName`, `getAddress`, `getCity`, `getTelephone`, and
   `getId` properties and iterates `Owner.getPets()` (and each pet's visits) to
   render the HTML response.

If no owner has that id, the first lookup in `findOwner` returns an empty
`Optional`, so its `orElseThrow` raises `IllegalArgumentException` with the
`Owner not found with id: ...` message before `showOwner` is entered. The normal
Spring Boot error handling then renders `src/main/resources/templates/error.html`
(normally an HTTP 500 because this exception is not mapped by an application
controller). `showOwner` contains a second, defensive `orElseThrow` for the same
condition if its own lookup were ever empty.

## 2. The owner-ID mismatch check

Under normal form submission, the check in
`OwnerController.processUpdateOwnerForm` (`OwnerController.java:152-156`) cannot
normally trigger. Two separate methods make the equality predetermined:

- `OwnerController.findOwner` (`OwnerController.java:64-70`) runs as the
  `@ModelAttribute("owner")` factory before binding and loads the entity using
  the URL's `ownerId`, so the bound `Owner` already has that URL id.
- `OwnerController.setAllowedFields` (`OwnerController.java:59-62`) is an
  `@InitBinder` method that calls `dataBinder.setDisallowedFields("id", "*.id")`.
  Therefore a submitted `id` (or nested id) cannot overwrite the id loaded from
  the URL. The normal owner form in
  `src/main/resources/templates/owners/createOrUpdateOwnerForm.html:8-15` does
  not submit an id either.

Consequently `owner.getId()` and the `ownerId` path variable are equal by
construction; the mismatch branch is a defensive check, not the mechanism that
prevents form id tampering.

## 3. The `vets` cache

This is not a staleness bug in the current repository design. In
`src/main/java/org/springframework/samples/petclinic/vet/VetRepository.java`,
`VetRepository` extends the marker interface `Repository<Vet, Integer>` (line 38)
and exposes exactly two methods: `findAll()` returning `Collection<Vet>` (lines
44-46) and `findAll(Pageable)` returning `Page<Vet>` (lines 54-56). It exposes no
`save`, `delete`, `deleteAll`, `findById`, or other mutation method.

Both methods are read-only (`@Transactional(readOnly = true)`) and cache their
results in `"vets"`. Since this repository cannot mutate a vet, there is no
repository write operation that needs to evict or refresh that cache; the lack of
an eviction policy in `CacheConfiguration` (`CacheConfiguration.java:35-50`) is
therefore intentional for the methods this interface exposes. External database
changes could of course make any in-process read cache stale, but that is outside
the mutation surface of this application.

## 4. Adding `someField` to `Owner`

The application will usually still start, but the existing database schema will
not gain a column. `src/main/resources/application.properties:10` sets
`spring.jpa.hibernate.ddl-auto=none`, so Hibernate neither creates nor alters
tables for the newly mapped field. With the configured snake-case physical naming
strategy (`application.properties:12`), `someField` is mapped as `some_field`.

Hibernate will include that mapped column in owner SELECTs and in an owner INSERT
or UPDATE. Thus an update can fail while `OwnerController.findOwner` is loading
the existing owner, and an insert/update that reaches `OwnerRepository.save`
will fail at the database with a missing-column/SQL grammar error; the owner is
not persisted. A getter/setter alone does not change this because the JPA mapping
is already part of the entity metadata.

To make it persist, add the matching `some_field` column to all schema variants:

- `src/main/resources/db/h2/schema.sql`
- `src/main/resources/db/mysql/schema.sql`
- `src/main/resources/db/postgres/schema.sql`

`application.properties:3` selects the schema location from the `database`
property; the profile files set that property to `mysql` or `postgres` (and the
default is `h2`).

## 5. Why the default test run shows two skips

The class is
`src/test/java/org/springframework/samples/petclinic/MySqlIntegrationTests.java`.
It has two `@Test` methods, `findAll` (lines 61-65) and `ownerDetails` (lines
67-72), and the class-level annotation
`@Testcontainers(disabledWithoutDocker = true)` at line 43. When the default
run has no reachable Docker daemon, Testcontainers disables the class's container
instead of failing, so JUnit/Surefire reports those two tests as skipped.
