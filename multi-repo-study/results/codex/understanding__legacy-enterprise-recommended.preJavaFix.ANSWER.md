# Answers

## 1. Repository implementations and the runtime default

The three implementation packages are:

- `org.springframework.samples.petclinic.repository.jpa`
- `org.springframework.samples.petclinic.repository.jdbc`
- `org.springframework.samples.petclinic.repository.springdatajpa`

For `OwnerRepository`, the corresponding implementation classes are
`JpaOwnerRepositoryImpl`, `JdbcOwnerRepositoryImpl`, and
`SpringDataOwnerRepository`.

The no-extra-JVM-argument default is determined in
`src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java`:

- line 52 declares `SPRING_PROFILE = "jpa"`;
- line 58 executes `rootAppContext.getEnvironment().setDefaultProfiles(SPRING_PROFILE)`.

Therefore the active default is the `jpa` profile and the `repository.jpa` implementation.
`src/main/resources/spring/business-config.xml` then wires that profile at line 91 with
`<context:component-scan base-package="org.springframework.samples.petclinic.repository.jpa"/>`.
It is not the one a package-name-only guess would most likely choose: the
`springdatajpa` package is not the default.

## 2. Shared service-test base and profile selection

The shared base class is
`src/test/java/org/springframework/samples/petclinic/service/AbstractClinicServiceTests.java`,
class `AbstractClinicServiceTests` (line 53). The three subclasses are:

- `ClinicServiceJpaTests`, in `ClinicServiceJpaTests.java`, extends the base at line 17 and
  has `@ActiveProfiles("jpa")` at line 16.
- `ClinicServiceSpringDataJpaTests`, in `ClinicServiceSpringDataJpaTests.java`, extends the
  base at line 15 and has `@ActiveProfiles("spring-data-jpa")` at line 14.
- `ClinicServiceJdbcTests`, in `ClinicServiceJdbcTests.java`, extends the base at line 31 and
  has `@ActiveProfiles("jdbc")` at line 30.

`@ActiveProfiles` is the mechanism: Spring Test activates the annotation's profile value
when loading each subclass's test `ApplicationContext`, so the same inherited tests run
against the repository beans selected by that profile.

## 3. Effect of adding a persisted `Owner` field

Consider first `repository.jpa`, specifically
`src/main/java/org/springframework/samples/petclinic/repository/jpa/JpaOwnerRepositoryImpl.java`.
No repository-implementation change is needed for an ordinary mapped field:

- `findByLastName` (lines 53–58) selects the `Owner` entity with JPQL;
- `findById` (lines 62–68) also selects the entity;
- `save` (lines 71–79) calls `EntityManager.persist` for a new owner or `merge` for an
  existing owner.

Hibernate obtains the new column value from the updated `Owner` entity mapping. The field
itself still needs a Java property (normally a field plus getter/setter) and a matching
`@Column(name = "...")` in `Owner`, and the database schema must contain the column, but
none of the three methods above needs a new column name or query fragment.

For `repository.jdbc`, specifically
`src/main/java/org/springframework/samples/petclinic/repository/jdbc/JdbcOwnerRepositoryImpl.java`,
manual repository edits are required for the hand-written SQL:

- add the column to the `SELECT` in `findByLastName`, line 73;
- add it to the `SELECT` in `findById`, line 93; otherwise
  `BeanPropertyRowMapper.newInstance(Owner.class)` at line 97 cannot populate it;
- add `new_column=:newProperty` to the `UPDATE owners SET` list at line 130, otherwise
  edits to an existing owner never write it.

The insert path has no literal column list in this class: the constructor creates a
`SimpleJdbcInsert` for `owners` at lines 56–58, and `save` passes a
`BeanPropertySqlParameterSource(owner)` at lines 123–125. Thus there is no separate
`INSERT` SQL string to edit here; it relies on the bean property and table metadata for
new-owner inserts. The explicit read and update SQL still must be changed, along with
the `Owner` property and schema.

The JDBC implementation requires more manual work because it hand-writes the owner
`SELECT` lists and `UPDATE` assignments. JPA's entity-oriented JPQL plus `persist`/`merge`
lets the ORM include an ordinary newly mapped column automatically.

## 4. `PetclinicInitializer` contexts and encoding filter

`src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java` creates:

1. `rootAppContext`, an `XmlWebApplicationContext`, in
   `createRootApplicationContext()` (lines 55–59). It loads
   `classpath:spring/business-config.xml` and
   `classpath:spring/tools-config.xml` (line 57). The business file contains the
   service/repository and persistence-profile wiring; the tools file contains the
   cross-cutting tools such as caching and monitoring.
2. `webAppContext`, another `XmlWebApplicationContext`, in
   `createServletApplicationContext()` (lines 63–67). It loads
   `classpath:spring/mvc-core-config.xml` (line 65). That file imports
   `mvc-view-config.xml` at line 17, which supplies the JSP view resolver at line 27
   (`/WEB-INF/jsp/` prefix and `.jsp` suffix).

`getServletFilters()` (lines 74–79) constructs one
`CharacterEncodingFilter("UTF-8", true)`. Returning it in the filter array registers
the filter for the servlet's requests, forces UTF-8 request/response encoding, and
supports entering characters such as Chinese characters in the owner form (the source
comment is at line 76).

## 5. Invalid submission of the new-owner form

For `POST /owners/new`, the application-level sequence is:

1. Spring MVC dispatches the request to `OwnerController.processCreationForm` in
   `src/main/java/org/springframework/samples/petclinic/web/OwnerController.java`,
   selected by `@PostMapping(value = "/owners/new")` at line 60.
2. MVC binds request parameters into an `Owner` and processes the `@Valid` annotation on
   the method parameter at line 61. Bean Validation checks the inherited
   `Person.firstName` and `Person.lastName` constraints in
   `src/main/java/org/springframework/samples/petclinic/model/Person.java` lines 30–36,
   and `Owner`'s `address`, `city`, and `telephone` constraints in
   `Owner.java` lines 46–57. A blank required value creates a field error in the
   adjacent `BindingResult` parameter.
3. `processCreationForm` calls `result.hasErrors()` at line 62. It is true, so the method
   returns `VIEWS_OWNER_CREATE_OR_UPDATE_FORM` at line 63, whose value is
   `owners/createOrUpdateOwnerForm` (line 41). It does not call
   `ClinicService.saveOwner` at line 66 and does not redirect at line 67.
4. The servlet-context view configuration resolves that logical name to
   `src/main/webapp/WEB-INF/jsp/owners/createOrUpdateOwnerForm.jsp` using the JSP
   prefix/suffix described above. The JSP's `<form:form modelAttribute="owner">` is at
   line 13, and it invokes `petclinic:inputField` for each field at lines 15–19.
5. Each invocation expands
   `src/main/webapp/WEB-INF/tags/inputField.tag`. Its `<spring:bind path="${name}">`
   at line 9 exposes the field status; when `status.error` is true, line 10 adds the
   `has-error` CSS class, lines 20–21 show the error icon, and line 22 renders
   `status.errorMessage`. The `form:input` at line 16 is rendered with the bound value.
   For a default blank `@NotEmpty` violation, the message is `must not be empty`, so
   the same form is shown again with the invalid field highlighted and its inline error
   message, rather than a success redirect.
