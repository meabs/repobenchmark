---
name: add-controller-page
description: Add a new @Controller class and JSP view in this codebase — the MVC wiring conventions (view name constants, ClinicService injection, form binding, redirect-after-POST) and where the JSP actually lives.
---

# Add a controller + view

1. Controllers live flat in `.../web/` (`OwnerController`, `PetController`,
   `VisitController`, `VetController`, `CrashController`) — one class per resource,
   `@Controller`-annotated, injecting `ClinicService` via constructor (never a
   concrete repository).
2. View names are string constants at the top of the class (e.g.
   `VIEWS_OWNER_CREATE_OR_UPDATE_FORM = "owners/createOrUpdateOwnerForm"`), returned
   from handler methods — match this pattern rather than inlining view-name strings.
3. JSPs live under `src/main/webapp/WEB-INF/jsp/<resource>/<name>.jsp` — the string
   constant's value is the path relative to that directory, no `.jsp` suffix. A new
   view needs both the controller method returning its name AND the JSP file at the
   matching path — one without the other fails silently at request time, not compile
   time.
4. Form pages follow a GET-to-show / POST-to-process pair (see
   `initCreationForm`/`processCreationForm` in `OwnerController`): the GET handler
   puts a fresh or loaded entity on the model, the POST handler takes `@Valid
   <Entity>` + `BindingResult`, returns the same form view on `result.hasErrors()`,
   otherwise calls `clinicService.save<Entity>(...)` and redirects
   (`"redirect:/owners/" + owner.getId()`-style) — don't render a view directly
   after a successful POST.
5. If the controller reads or writes a field you just added to a model, make sure
   the JSP form actually includes an input/display for it — a model field with no
   JSP change is invisible to a real user even if the backend fully supports it.
6. This module has no Playwright/e2e layer — verifying a UI change means starting
   the app (see `readme.md` for the Maven Jetty/Tomcat run command) and checking the
   page by hand, or adding a `MockMvc`-based `web/*ControllerTests` assertion.
