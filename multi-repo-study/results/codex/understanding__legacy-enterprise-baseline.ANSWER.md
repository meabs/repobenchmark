# Answers

## 1. Repository implementations and the runtime default

The three `OwnerRepository` implementation packages are:

- `org.springframework.samples.petclinic.repository.jdbc`, containing `JdbcOwnerRepositoryImpl.java`.
- `org.springframework.samples.petclinic.repository.jpa`, containing `JpaOwnerRepositoryImpl.java`.
- `org.springframework.samples.petclinic.repository.springdatajpa`, containing `SpringDataOwnerRepository.java`.

The no-argument runtime choice is determined in `src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java:52`:

```java
private static final String SPRING_PROFILE = "jpa";
```

`createRootApplicationContext()` applies that value as the default profile at line 58 with `rootAppContext.getEnvironment().setDefaultProfiles(SPRING_PROFILE)`. Therefore the active implementation is `org.springframework.samples.petclinic.repository.jpa.JpaOwnerRepositoryImpl`. In `src/main/resources/spring/business-config.xml`, the `jpa` profile scans that package at lines 84–92; the `jdbc` and `spring-data-jpa` profiles select the other two packages at lines 66–82 and 94–96. Package names alone do not select a bean: the explicit default is `jpa`. It happens to be the implementation one might guess from the package names, but that is configuration, not package-name precedence; `-Dspring.profiles.active=...` can override the default.

## 2. Shared repository/service integration tests

The shared base class is `org.springframework.samples.petclinic.service.AbstractClinicServiceTests` in `src/test/java/org/springframework/samples/petclinic/service/AbstractClinicServiceTests.java:53`.

Its three subclasses are:

- `ClinicServiceJdbcTests` (`.../ClinicServiceJdbcTests.java:31`) extends the base and has `@ActiveProfiles("jdbc")` at line 30.
- `ClinicServiceJpaTests` (`.../ClinicServiceJpaTests.java:17`) extends the base and has `@ActiveProfiles("jpa")` at line 16.
- `ClinicServiceSpringDataJpaTests` (`.../ClinicServiceSpringDataJpaTests.java:15`) extends the base and has `@ActiveProfiles("spring-data-jpa")` at line 14.

Each class also loads `classpath:spring/business-config.xml` through `@SpringJUnitConfig`. Spring Test's `@ActiveProfiles` puts that exact profile into the test `ApplicationContext` environment. The profile then activates the matching `<beans profile="...">` section in `business-config.xml`, so only the corresponding repository package is component-scanned or Spring-Data-scanned.

## 3. Adding a persisted `Owner` field

Consider first `JpaOwnerRepositoryImpl` in `src/main/java/org/springframework/samples/petclinic/repository/jpa/JpaOwnerRepositoryImpl.java`. If a new field (for example, `email`) is added to `Owner` with a JPA mapping such as `@Column(name = "email")`, and the database schema is migrated, this repository implementation needs no source change. `findByLastName()` (lines 53–59) and `findById()` (lines 62–68) select the `Owner` entity, not a hand-written scalar projection, so JPA hydrates the newly mapped field. `save()` (lines 71–79) calls `EntityManager.persist()` for new owners and `EntityManager.merge()` for existing owners, both of which include mapped state. The entity and each supported database schema still need the new mapping/column; the repository class does not.

For contrast, `JdbcOwnerRepositoryImpl` in `src/main/java/org/springframework/samples/petclinic/repository/jdbc/JdbcOwnerRepositoryImpl.java` requires manual repository changes. Its `findByLastName()` SQL explicitly selects only `id, first_name, last_name, address, city, telephone` at lines 72–79, and `findById()` repeats that projection at lines 92–98. The new column must be added to both projections for `BeanPropertyRowMapper` to populate the new JavaBean property. Its update SQL is also explicit: the `SET` list at lines 128–134 must add `new_column=:newField`. The insert path is less manual: `SimpleJdbcInsert` is configured with the `owners` table and generated key at lines 56–58, and `BeanPropertySqlParameterSource` is created from the owner at line 123; with the new table column and getter/setter, that metadata/property-based insert can include it. The schema scripts still need the new column.

The JDBC implementation requires more manual work because its read and update SQL are hard-coded column-by-column. The JPA implementation delegates entity-field selection and persistence to the ORM mapping.

## 4. `PetclinicInitializer` and its contexts

`PetclinicInitializer` creates two `XmlWebApplicationContext`s:

1. `createRootApplicationContext()` (lines 55–60) creates `rootAppContext`. It directly loads `classpath:spring/business-config.xml` and `classpath:spring/tools-config.xml` at line 57, and sets the default profile at line 58. `business-config.xml` in turn imports `datasource-config.xml` at line 16.
2. `createServletApplicationContext()` (lines 63–67) creates `webAppContext`. It directly loads `classpath:spring/mvc-core-config.xml` at line 65. That file imports `mvc-view-config.xml` at `src/main/resources/spring/mvc-core-config.xml:17`, which supplies the JSP view resolver (`/WEB-INF/jsp/` prefix and `.jsp` suffix at `mvc-view-config.xml:25–28`).

`getServletFilters()` (lines 75–79) registers one `CharacterEncodingFilter`, constructed as `new CharacterEncodingFilter("UTF-8", true)`. It forces UTF-8 request and response encoding; the nearby comment says this is to allow Chinese characters in the Owner form. The initializer returns it for the DispatcherServlet mapping (`getServletMappings()` returns `/` at lines 69–72).

## 5. New-owner submission with a validation error

For `POST /owners/new`, the application-level sequence is:

1. Spring MVC dispatches the request to `OwnerController` (`src/main/java/org/springframework/samples/petclinic/web/OwnerController.java`). Before binding, its `@InitBinder` method `setAllowedFields(WebDataBinder)` (lines 48–51) configures the binder to disallow `id`.
2. Spring's MVC argument resolver binds request parameters to a new `Owner` object and processes the `@Valid` annotation on `Owner` in `processCreationForm(@Valid Owner owner, BindingResult result)` at lines 60–61. Bean Validation sees the inherited `Person.firstName` and `Person.lastName` `@NotEmpty` constraints (`Person.java:30–36`) and the `Owner.address`, `city`, and `telephone` `@NotEmpty` constraints (`Owner.java:46–57`); `telephone` also has `@Digits` at lines 54–57. The validation errors are placed in the adjacent `BindingResult`.
3. Spring invokes `OwnerController.processCreationForm()` (line 61). `result.hasErrors()` at line 62 is true, so the method returns `VIEWS_OWNER_CREATE_OR_UPDATE_FORM`, whose value is `owners/createOrUpdateOwnerForm` at line 41. It does not call `ClinicService.saveOwner()` at line 66, and no repository method runs.
4. `DispatcherServlet` resolves that logical view using the JSP resolver configured by `mvc-view-config.xml`, producing `/WEB-INF/jsp/owners/createOrUpdateOwnerForm.jsp`.
5. The JSP's `<form:form modelAttribute="owner">` at line 13 renders the same bound `Owner` and invokes the `petclinic:inputField` tag for each field at lines 15–19. `src/main/webapp/WEB-INF/tags/inputField.tag:9–23` calls `<spring:bind path="${name}">`; it tests `status.error` at lines 10, 17, and 20, adds the `has-error` CSS class, renders the input with `<form:input path="${name}">` at line 16, and, for an invalid field, emits the error icon and `${status.errorMessage}` at lines 20–22. Thus the form is returned with the user's entered values, the offending blank field marked in error, and the Bean Validation message (for `@NotEmpty`, Hibernate Validator's default is “must not be empty”) shown beside it.

