---
name: add-offer-condition-or-benefit
description: Add a new promotions Condition or Benefit type to the offer app (e.g. a custom "buy from category X" condition). Covers the proxy_class mechanism that Oscar's offer models use instead of plain subclassing, since a naive Django subclass will NOT be picked up.
---

# Add a custom offer Condition or Benefit

`Condition` and `Benefit` (`src/oscar/apps/offer/abstract_models.py`,
`AbstractCondition` / `AbstractBenefit`) are **not** meant to be subclassed
via normal Django model inheritance for new built-in-style types. Instead
they use a `proxy_class` field (a `NullCharField` storing a dotted import
path) plus a `proxy()` method that instantiates that class as a Python-level
proxy over the same DB row — `proxy_map` shows the pattern for the three
built-in condition types (`CountCondition`, `ValueCondition`,
`CoverageCondition`, loaded via `get_class("offer.conditions", ...)`).

1. Write your new condition/benefit as a plain Python class (not a new Django
   model) that mirrors one of `src/oscar/apps/offer/conditions.py` or
   `benefits.py` — implement `is_satisfied(self, offer, basket)` (Condition)
   or the equivalent apply method (Benefit); look at `CountCondition` in
   `conditions.py` as the template.
2. Register it so it's loadable via `get_class`/`get_classes` — either by
   adding it into `oscar.apps.offer.conditions`/`benefits` directly if this
   is a framework-level addition, or, if you're working as a downstream
   project, via the `override-app` skill's fork pattern.
3. A `Condition`/`Benefit` row picks up your custom behavior by having its
   `proxy_class` field set to the dotted path of your class — this is a data
   value, not a schema change, so no migration is needed just to use a new
   condition type once it exists as code (a migration IS needed only if you
   add new model fields to `AbstractCondition`/`AbstractBenefit` themselves —
   see `add-model-field`).
4. Add a test under `tests/` for the app that already covers `offer`
   conditions/benefits — check `is_satisfied`/apply behavior directly against
   a constructed basket, matching the style of existing condition/benefit
   tests rather than going through the full checkout flow.
