---
type: concept
title: Controllers — routing, form binding, pagination
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:39:22Z
sources:
  - src/main/java/org/springframework/samples/petclinic/owner/OwnerController.java
  - src/main/java/org/springframework/samples/petclinic/owner/PetController.java
  - src/main/java/org/springframework/samples/petclinic/vet/VetController.java
  - src/main/java/org/springframework/samples/petclinic/system/CrashController.java
  - src/main/resources/application.properties
---

# Controllers

All controllers are `@Controller` (package-private classes) returning Thymeleaf view
names as plain strings, or a `ModelAndView` when more than one model object needs
setting at once (`OwnerController.showOwner`). There is no separate JSON API for the
UI — the one exception is `VetController.showResourcesVetList` at `GET /vets`,
which is `@ResponseBody` and returns a `Vets` wrapper object (JSON), kept alongside
the HTML `/vets.html` listing page for programmatic consumers.

## Mass-assignment protection

Both `OwnerController` and `PetController` register `@InitBinder` methods that call
`dataBinder.setDisallowedFields("id", "*.id")` — form-bound `id` values are always
ignored. This is what actually makes update flows safe: `OwnerController.findOwner`
(the `@ModelAttribute("owner")` method) already fetches the persisted entity by the
*path* `ownerId` before the disallowed-fields binder runs, so the entity's real id
is set from the URL, not from anything the client submitted in the form body.

**Consequence worth knowing**: in `OwnerController.processUpdateOwnerForm`, the
check `if (!Objects.equals(owner.getId(), ownerId))` (comparing the bound entity's
id against the path variable) is effectively unreachable during normal form
submission — `owner.getId()` can only be non-null because `findOwner` already set it
from `ownerId`, and the form can't override it (id is disallowed), so the two values
are the same by construction, not by validation. Don't read this line as an active
guard against a spoofed id in the form body — the disallowed-fields binder is what
does that job.

## Pagination

`OwnerController.processFindForm` and `VetController.showVetList` share the same
convention: page size 5, `PageRequest.of(page - 1, 5)` (1-indexed in the URL, 0-indexed
internally), and a private `addPaginationModel` helper that adds
`currentPage`/`totalPages`/`totalItems`/`list<Entity>` to the model — the shared
Thymeleaf pagination fragment expects exactly those attribute names. Any new list
page should reuse this shape rather than inventing new model attribute names.

## `CrashController`

`GET /oups` deliberately throws a `RuntimeException` — it exists purely to
demonstrate the app's `error.html` view resolution, not a real bug.

## Actuator exposure

`application.properties` sets `management.endpoints.web.exposure.include=*`,
exposing every actuator endpoint (env, beans, heapdump, etc.) — the file's own
comment flags this as dev/test-only, not something to carry into a production
profile unmodified.
