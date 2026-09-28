# Answers

## 1. Repository implementations and the runtime default

\`OwnerRepository\` is implemented in these three sibling packages:

- \`org.springframework.samples.petclinic.repository.jpa\` — \`JpaOwnerRepositoryImpl.java\`
- \`org.springframework.samples.petclinic.repository.jdbc\` — \`JdbcOwnerRepositoryImpl.java\`
- \`org.springframework.samples.petclinic.repository.springdatajpa\` — \`SpringDataOwnerRepository.java\`

The operative default is set in \`src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java:58\`, where \`createRootApplicationContext()\` calls:

\`\`\`java
rootAppContext.getEnvironment().setDefaultProfiles(SPRING_PROFILE);
\`\`\`

\`SPRING_PROFILE\` is \`"jpa"\` at line 52, so the active implementation with no overriding JVM property is \`repository.jpa.JpaOwnerRepositoryImpl\`. The profile-to-package wiring is in \`src/main/resources/spring/business-config.xml:84-92\`. This is not necessarily the package one would guess from the names: \`springdatajpa\` is not the default; \`jpa\` is. An explicit \`-Dspring.profiles.active=jdbc\` or \`-Dspring.profiles.active=spring-data-jpa\` can override it.

## 2. Shared service-test base and profile selection

The base class is \`src/test/java/org/springframework/samples/petclinic/service/AbstractClinicServiceTests.java\`, class declaration at line 53. Its three subclasses are:

- \`ClinicServiceJpaTests\` — \`@ActiveProfiles("jpa")\` at line 16; \`@SpringJUnitConfig(locations = {"classpath:spring/business-config.xml"})\` at line 15.
- \`ClinicServiceSpringDataJpaTests\` — \`@ActiveProfiles("spring-data-jpa")\` at line 14; the same \`@SpringJUnitConfig\` location at line 13.
- \`ClinicServiceJdbcTests\` — \`@ActiveProfiles("jdbc")\` at line 30; the same \`@SpringJUnitConfig\` location at line 29.

Each subclass extends \`AbstractClinicServiceTests\` (respectively lines 17, 15, and 31). Spring TestContext reads the \`@ActiveProfiles\` value and activates that profile while loading \`business-config.xml\`; its profile block component-scans the corresponding JPA/JDBC package or enables the Spring Data repository package.

## 3. Adding an \`Owner\` field: JPA versus JDBC

For the \`jpa\` implementation, \`src/main/java/org/springframework/samples/petclinic/repository/jpa/JpaOwnerRepositoryImpl.java\` needs no repository-code change for an ordinary persisted field. \`findByLastName()\` (lines 53-59) and \`findById()\` (lines 62-68) select the \`Owner\` entity with JPQL, while \`save()\` (lines 71-79) calls \`EntityManager.persist()\` or \`merge()\`. Hibernate therefore maps a new field declared on \`Owner\` (with its \`@Column\`) automatically. The model and database schema still need the field/column; only a custom query would require changing this repository.

For the \`jdbc\` implementation, \`src/main/java/org/springframework/samples/petclinic/repository/jdbc/JdbcOwnerRepositoryImpl.java\` does require manual repository changes. Add the new SQL column to the \`SELECT\` lists in \`findByLastName()\` lines 72-79 and \`findById()\` lines 92-98 so \`BeanPropertyRowMapper<Owner>\` can populate it, and add \`field=:field\` (with the matching Java property parameter) to the \`UPDATE\` at lines 128-134. The insert path at lines 123-126 uses \`BeanPropertySqlParameterSource(owner)\` with \`SimpleJdbcInsert\` configured only with the table and generated key, so there is no hand-written insert column list to edit; a matching schema column and JavaBean property let its metadata-driven insert include the value. The JDBC implementation requires more manual work because it hand-writes the read and update SQL, whereas the JPA implementation delegates column mapping to Hibernate.

## 4. \`PetclinicInitializer\` contexts and encoding filter

\`src/main/java/org/springframework/samples/petclinic/PetclinicInitializer.java\` creates:

1. The root \`XmlWebApplicationContext\` in \`createRootApplicationContext()\` (lines 55-59). It loads \`classpath:spring/business-config.xml\` and \`classpath:spring/tools-config.xml\` (line 57). The business context contains service/repository configuration; the tools context contains infrastructure such as caching and monitoring.
2. The servlet/DispatcherServlet \`XmlWebApplicationContext\` in \`createServletApplicationContext()\` (lines 63-67). It loads \`classpath:spring/mvc-core-config.xml\` (line 65), which imports \`mvc-view-config.xml\` at line 17 for JSP view resolution.

\`getServletFilters()\` (lines 74-79) registers a \`CharacterEncodingFilter("UTF-8", true)\`: it forces UTF-8 request/response encoding, specifically documented in the source as allowing Chinese characters in the Owner form (line 76).

## 5. New-owner POST with validation errors

For \`POST /owners/new\`, the flow is:

1. Spring MVC binds request parameters to a new \`Owner\` and runs Bean Validation because the handler parameter is \`@Valid Owner owner\` in \`OwnerController.processCreationForm(...)\` at \`src/main/java/org/springframework/samples/petclinic/web/OwnerController.java:60-67\`. A blank required field violates \`@NotEmpty\`: \`firstName\`/\`lastName\` are declared in \`Person.java:30-35\`; \`address\`/\`city\`/\`telephone\` are declared in \`Owner.java:46-57\` (telephone also has \`@Digits\`). Binding/validation errors are placed in the adjacent \`BindingResult result\`.
2. \`OwnerController.processCreationForm\` calls \`result.hasErrors()\` at line 62. It is true, so the method returns \`VIEWS_OWNER_CREATE_OR_UPDATE_FORM\` at line 63, whose value at line 41 is \`owners/createOrUpdateOwnerForm\`. It does not call \`ClinicService.saveOwner()\`; that call at line 66 is only on the no-error path.
3. The view resolver configured by \`src/main/resources/spring/mvc-view-config.xml:25-28\` maps that logical view to \`/WEB-INF/jsp/owners/createOrUpdateOwnerForm.jsp\`. The JSP's \`<form:form modelAttribute="owner">\` is at lines 13-19.
4. Each \`petclinic:inputField\` invokes \`src/main/webapp/WEB-INF/tags/inputField.tag\`. Its \`spring:bind\` at line 9 exposes the field status; lines 10 and 20-23 add the error styling/icon and render \`\${status.errorMessage}\` in the \`help-inline\` span. Thus the form is rendered again with the submitted values and the validation message beside the invalid field. The message source is \`ResourceBundleMessageSource\` in \`mvc-core-config.xml:53-54\`, with the \`required\` message supplied by \`src/main/resources/messages/messages.properties:2\` (\`required=is required\`).
