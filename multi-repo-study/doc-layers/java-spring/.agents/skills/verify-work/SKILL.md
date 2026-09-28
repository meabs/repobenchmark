---
name: verify-work
description: How to actually confirm a change works in this repo, not just that it compiles — the build-blocking format gate and the i18n sync test that a plain `./mvnw test` reads as "just more tests" but that fail for reasons unrelated to the change's logic.
---

# Verify your work actually works

`./mvnw -q -B test` alone is not enough to trust a change here. Before calling
anything done:

1. **Formatting is build-blocking, not a style nit.** This repo runs
   `io.spring.javaformat:spring-javaformat-maven-plugin` bound to `validate`,
   which runs *before* `test` in the Maven lifecycle. A formatting violation
   fails the whole build with zero tests executed — it looks like "everything is
   broken" when it's actually just whitespace/import order. Run
   `./mvnw spring-javaformat:apply` on any file you touched before running tests,
   or match the exact formatting of the surrounding code by eye (4-space indent,
   one blank line between members, no wildcard imports).
2. **If you added or changed any user-facing text** (a Thymeleaf template label,
   a validation message, anything rendered to a browser), check whether it's
   sourced from a message key rather than hardcoded. This repo ships translated
   `messages_*.properties` files (multiple locales) alongside the default
   `messages.properties`, and `I18nPropertiesSyncTest` fails the build if a key
   exists in one locale file but not the others. Adding a new key means adding it
   to **every** `messages_*.properties` file, not just the default one — even a
   placeholder/untranslated value is enough to keep the test green; leaving a
   locale file out is the actual failure.
3. Only after both of the above are true, run `./mvnw -q -B test` and read the
   surefire summary yourself (`target/surefire-reports/*.txt`) rather than
   assuming a non-crashing agent run means the tests passed.
