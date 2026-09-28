# Answers

## 1. Repository implementations and the runtime choice

The three sibling implementation packages are:

- `org.springframework.samples.petclinic.repository.jdbc`
- `org.springframework.samples.petclinic.repository.jpa`
- `org.springframework.samples.petclinic.repository.springdatajpa`

For `OwnerRepository`, the corresponding types are `JdbcOwnerRepositoryImpl.java`,
`JpaOwnerRepositoryImpl.java`, and `SpringDataOwnerRepository.java`.

The no-argument runtime choice is determined in
`src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java`:
line 52 sets `SPRING_PROFILE` to `"jpa"`, and line 58 calls
`rootAppContext.getEnvironment().setDefaultProfiles(SPRING_PROFILE)`.  With no
`spring.profiles.active` JVM property, the default is therefore `jpa`; then
`src/main/resources/spring/business-config.xml` line 91 component-scans the JPA
package (`org.springframework.samples.petclinic.repository.jpa`).  It is not
possible to infer the active implementation from the package names alone; the
explicit initializer default selects the ordinary JPA implementation, not the
Spring Data JPA one.  A JVM `-Dspring.profiles.active=...` value overrides this
default.

## 2. Shared repository-implementation tests

The base class is
`src/test/java/org/springframework/samples/petclinic/service/AbstractClinicServiceTests.java`,
declared at line 53.  Its subclasses are:

- `ClinicServiceJdbcTests.java`: line 30 uses `@ActiveProfiles("jdbc")`.
- `ClinicServiceJpaTests.java`: line 16 uses `@ActiveProfiles("jpa")`.
- `ClinicServiceSpringDataJpaTests.java`: line 14 uses
  `@ActiveProfiles("spring-data-jpa")`.

All three also use `@SpringJUnitConfig(locations = {"classpath:spring/business-config.xml"})`
(respectively lines 29, 15, and 13).  Spring TestContext activates the value
from `@ActiveProfiles`, so the profile blocks in `business-config.xml` create
the selected repository beans while the inherited tests exercise them.

## 3. Adding a persisted `Owner` field

Compare the JPA and JDBC implementations.

With `JpaOwnerRepositoryImpl` (`src/main/java/org/springframework/samples/petclinic/repository/jpa/JpaOwnerRepositoryImpl.java`),
the repository implementation itself normally needs no change.  Its queries at
lines 56 and 65 select the `Owner` entity (`SELECT ... owner`), rather than an
explicit field list, and `save` at lines 72–77 calls `EntityManager.persist`
for a new owner or `EntityManager.merge` for an existing one.  After adding a
JPA-mapped field to `Owner`, the required changes are the entity mapping and
the database schema (and any seed/schema variants), not this repository class;
JPA reads and writes the mapped field as part of the entity.

With `JdbcOwnerRepositoryImpl` (`src/main/java/org/springframework/samples/petclinic/repository/jdbc/JdbcOwnerRepositoryImpl.java`),
more manual work is required.  `findByLastName` has an explicit owner column
list at lines 72–76, and `findById` has another at lines 92–95; both must add
the new column for `BeanPropertyRowMapper` (lines 78 and 97) to populate the
new Java property.  The update SQL at lines 128–132 must also add the new
`SET` assignment.  The insert path at lines 123–126 uses
`BeanPropertySqlParameterSource` with `SimpleJdbcInsert`, so a matching bean
property can be included automatically by the insert metadata, but the new
database column is still required and the explicit read/update SQL remains
the developer's responsibility.  Thus JDBC requires more manual work because
its SQL spells out the selected and updated columns; JPA delegates that field
mapping to the entity persistence provider.

## 4. `PetclinicInitializer` contexts and encoding filter

`src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java`
creates two `XmlWebApplicationContext` instances:

1. `createRootApplicationContext()` (lines 55–59) creates `rootAppContext` and
   loads `classpath:spring/business-config.xml` and
   `classpath:spring/tools-config.xml` (line 57).  `business-config.xml` in
   turn imports `datasource-config.xml` at its line 16.
2. `createServletApplicationContext()` (lines 63–66) creates `webAppContext`
   and loads `classpath:spring/mvc-core-config.xml` (line 65).
   `mvc-core-config.xml` imports `mvc-view-config.xml` at its line 17, so that
   view configuration is loaded transitively by the servlet context.

`getServletFilters()` (lines 74–79) returns a
`CharacterEncodingFilter("UTF-8", true)`: it forces UTF-8 request/response
encoding for the DispatcherServlet, including the owner form.  The comment at
line 76 identifies the purpose as allowing Chinese characters in the Owner
form.

## 5. New-owner submission with a validation error

For a `POST /owners/new` with, for example, a blank `address`, the sequence is:

1. Spring MVC binds request parameters into an `Owner` and invokes
   `OwnerController.setAllowedFields(WebDataBinder)` from the `@InitBinder`
   method at lines 48–51.  The binder disallows `id`.
2. Because the handler parameter is `@Valid Owner owner`, MVC's configured Bean
   Validation adapter/provider validates the bound object before entering the
   handler.  The constraints are `@NotEmpty` on `Person.firstName` and
   `Person.lastName` (lines 30–36 of `Person.java`) and on `Owner.address`,
   `Owner.city`, and `Owner.telephone` (lines 46–57 of `Owner.java`).  A blank
   required value produces a field error in the following `BindingResult`.
   The repository's `ValidatorTests` line 51 confirms the default
   `@NotEmpty` message is `must not be empty`.
3. MVC calls `OwnerController.processCreationForm(@Valid Owner, BindingResult)`
   at `OwnerController.java` lines 60–68.  `result.hasErrors()` at line 62 is
   true, so line 63 returns the logical view name
   `owners/createOrUpdateOwnerForm`.  `ClinicService.saveOwner` at line 66 is
   not called, and there is no redirect.
4. The servlet context's view configuration maps that logical name through the
   JSP resolver in `mvc-view-config.xml` lines 25–28: prefix
   `/WEB-INF/jsp/` plus suffix `.jsp` resolves it to
   `src/main/webapp/WEB-INF/jsp/owners/createOrUpdateOwnerForm.jsp`.
5. That JSP's `<form:form modelAttribute="owner">` (line 13) renders the
   bound values and invokes `petclinic:inputField` for each field (lines
   15–19).  In `src/main/webapp/WEB-INF/tags/inputField.tag`, `spring:bind`
   at line 9 exposes the field status; an error makes `cssGroup` include
   `has-error` (line 10), and lines 20–23 render the error icon and
   `${status.errorMessage}` (normally `must not be empty`) in a
   `help-inline` span.  The user sees the same new-owner form again, with the
   invalid field highlighted and its validation message displayed.
