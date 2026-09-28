# Log

- 2026-09-28: Bundle authored by reading `src/main/java/.../owner/{Owner,Pet,PetController,OwnerController,OwnerRepository}.java`,
  `vet/VetController.java`, `system/{CrashController,WelcomeController}.java`,
  `src/main/resources/application*.properties`, `src/main/resources/db/h2/schema.sql`,
  and `src/test/java/.../MySqlIntegrationTests.java` directly — no content here is
  inferred from the upstream project's README or external documentation, only from
  this repo's own source.
- 2026-09-28 (later): a real benchmark run against this bundle's original 4 skills
  failed two of two code-change cells (`simple_change`, `complex`) on this repo,
  both for reasons the original bundle never mentioned: the `spring-javaformat`
  Maven plugin blocks the whole build on a formatting violation before any test
  runs, and a real `I18nPropertiesSyncTest` fails if a new user-facing message key
  is added to `messages.properties` without adding it to every locale variant too.
  Neither gate is exotic or hidden — both are visible in `pom.xml` / `src/test` to
  anyone who looked — but the original bundle simply didn't surface them, and the
  agent runs that trusted the bundle's narrower, faster path skipped the broader
  exploration that would have caught them (the baseline arm, with no doc layer,
  passed both cells cleanly). Added a `verify-work` skill covering both gates and
  referenced it from `AGENTS.md`. This is a real, logged instance of the failure
  mode this bundle's own `index.md` already warns about in the abstract — treat
  every doc bundle as unverified until something has actually tried to work from
  it and failed doing so, not just until it reads as plausible.
