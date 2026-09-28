# Answers

## 1. `GET /owners/{ownerId}`

1. `src/main/java/org/springframework/samples/petclinic/owner/OwnerController.java`, `OwnerController.findOwner(...)` (lines 64–70), the class-level `@ModelAttribute("owner")`, runs before the mapped handler. Because `ownerId` is present, it calls `OwnerRepository.findById(Integer)` with that path value.
2. That repository method is declared in `src/main/java/org/springframework/samples/petclinic/owner/OwnerRepository.java` (lines 47–60). Spring Data JPA supplies its implementation and returns `Optional<Owner>`.
3. If the optional is present, dispatch proceeds to `OwnerController.showOwner(int)` (lines 169–177), mapped by `@GetMapping("/owners/{ownerId}")`. This method creates `ModelAndView("owners/ownerDetails")`, then calls `this.owners.findById(ownerId)` a second time, unwraps it, and adds the resulting `Owner` with `mav.addObject(owner)`.
4. Spring MVC resolves the returned view name to `src/main/resources/templates/owners/ownerDetails.html`, which reads the `owner` model attribute and renders the owner and its pets/visits.

There are therefore normally two `OwnerRepository.findById` calls: one in `findOwner` and one in `showOwner`. If no owner exists, the first call in `findOwner` returns `Optional.empty()` and its `orElseThrow(...)` raises `IllegalArgumentException` with an “Owner not found with id...” message; normal dispatch stops before `showOwner` and the details view is not rendered. `showOwner` contains a second, independent `orElseThrow(...)` for the same empty-result case (lines 172–174), although the preceding model-attribute lookup normally catches it first.

## 2. Why the ID-mismatch check is predetermined

Under normal form submission, the check in `OwnerController.processUpdateOwnerForm(...)` (lines 144–161) does not trigger. Two methods make that outcome effectively predetermined:

- `OwnerController.findOwner(...)` (lines 64–70) is the `@ModelAttribute("owner")` factory for the POST as well as the GET. It loads the existing `Owner` using the URL’s `ownerId` before form binding, so the bound object starts with that same ID.
- `OwnerController.setAllowedFields(WebDataBinder)` (lines 59–62) calls `setDisallowedFields("id", "*.id")`. Binding cannot replace the loaded ID from a submitted `id` parameter (and the normal owner form, `createOrUpdateOwnerForm.html`, does not render an ID input). Thus `owner.getId()` remains equal to the path `ownerId`, making `Objects.equals(...)` true and the negated condition false.

## 3. The `vets` cache has no in-application eviction bug

No, not for this codebase’s repository API. `src/main/java/org/springframework/samples/petclinic/vet/VetRepository.java` extends the minimal Spring Data `Repository<Vet, Integer>` and exposes only:

- `findAll()` returning `Collection<Vet>` (lines 40–46); and
- `findAll(Pageable)` returning `Page<Vet>` (lines 48–56).

Both are read-only transactions and both are `@Cacheable("vets")`. There is no `save`, `delete`, update, or other mutating method on `VetRepository` that would require cache eviction. `CacheConfiguration.petclinicCacheConfigurationCustomizer()` only creates the `vets` cache (lines 35–38), and its `cacheConfiguration()` enables statistics (lines 40–50). With vets effectively read-only through this application, an eviction policy is not required. The cache could of course become stale if vets are changed directly in the database or through some external writer.

## 4. Adding `someField` to `Owner`

The new field would be a valid JPA-mapped property, but saving an owner with it populated would fail when Hibernate flushes the insert/update: Hibernate would generate SQL referring to the physical column (normally `some_field` because of the configured snake-case naming strategy), while the existing `owners` table has no such column. The database would reject the statement with a missing/unknown-column SQL error, propagated as a persistence/data-access exception; the value would not be silently ignored or persisted.

The cause is `spring.jpa.hibernate.ddl-auto=none` in `src/main/resources/application.properties` (line 10). Hibernate does not alter or validate the schema to add the new column. The application instead initializes the schema from `spring.sql.init.schema-locations=classpath*:db/${database}/schema.sql` (line 3). To make the property persist, update the owners-table DDL in the schema used by the running profile:

- default H2: `src/main/resources/db/h2/schema.sql`;
- MySQL profile: `src/main/resources/db/mysql/schema.sql`; and
- PostgreSQL profile: `src/main/resources/db/postgres/schema.sql`.

For an already-existing database, apply the corresponding `ALTER TABLE` (or migration) as well; changing only the Java entity cannot change an existing table. If the value is to come from the HTML form, `src/main/resources/templates/owners/createOrUpdateOwnerForm.html` also needs an input, but that is separate from the database persistence requirement.

## 5. Why Maven reports two skipped tests

With Docker unavailable, `src/test/java/org/springframework/samples/petclinic/MySqlIntegrationTests.java` is disabled by `@Testcontainers(disabledWithoutDocker = true)` (line 43). The class has exactly two `@Test` methods, `findAll()` and `ownerDetails()` (lines 61–72), so both are reported skipped. That is why the default `./mvnw test` run typically ends with `Tests run: 74 ... Skipped: 2` while still succeeding.
