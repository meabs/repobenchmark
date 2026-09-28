---
name: add-service-method
description: Add a method to the ClinicService interface/ClinicServiceImpl — the transactional service layer between controllers and the 3 repository implementations.
---

# Add a service method

1. Declare the method on `ClinicService` (interface) in `.../service/`.
2. Implement it on `ClinicServiceImpl` in the same package, delegating to the
   appropriate `*Repository` interface (never call a `repository/jpa`,
   `repository/jdbc`, or `repository/springdatajpa` implementation class directly —
   always go through the plain interface in `.../repository/`, so the method works
   under whichever profile is active).
3. `ClinicServiceImpl` is `@Transactional` at the class level already — a new public
   method inherits that unless you override it. Only add a method-level
   `@Transactional(readOnly = true)` if the method is read-only and you want the
   optimization; don't add transaction annotations that duplicate the class default.
4. Add a test to `AbstractClinicServiceTests` (in
   `src/test/java/.../service/`) rather than to one of the three concrete
   `ClinicService*Tests` subclasses — it's inherited by all three and runs against
   every repository implementation automatically. See `run-the-right-tests`.
