---
name: add-read-view
description: Add a new read-only page in this repo — a controller method plus its Thymeleaf template — following the existing pagination and layout-fragment conventions (e.g. a new listing page in the style of VetController/vetList.html).
---

# Add a new read-only page

1. Add a package-private controller class (or method on an existing one) under
   `src/main/java/org/springframework/samples/petclinic/<area>/`, annotated
   `@Controller` (not `@RestController` — this app renders server-side HTML, it has
   no separate JSON API layer for the UI). Return the Thymeleaf view name as a
   plain string, or a `ModelAndView` if you need to add multiple model objects at
   once (see `OwnerController.showOwner`).
2. If the page lists more than a handful of rows, paginate like
   `VetController.showVetList`/`OwnerController.processFindForm` do: take
   `@RequestParam(defaultValue = "1") int page`, build a `PageRequest.of(page - 1,
   5)` (page size 5 is the convention across this codebase), and add
   `currentPage`/`totalPages`/`totalItems`/`list<Entity>` to the model — the
   pagination fragment in the templates expects exactly those attribute names.
3. Create the template under `src/main/resources/templates/<area>/<name>.html`,
   using `th:replace` / `th:insert` on `fragments/layout.html` the way
   `vets/vetList.html` and `owners/ownersList.html` do — don't write a standalone
   HTML page from scratch, the layout fragment carries the nav/header.
4. Add a `@WebMvcTest`-based controller test (mock the repository with
   `@MockitoBean`, not a real DB) in the style of `VetControllerTests` /
   `OwnerControllerTests` — assert both the response status/view name and that the
   expected model attributes are populated.
5. Run `./mvnw -q -B test`.
