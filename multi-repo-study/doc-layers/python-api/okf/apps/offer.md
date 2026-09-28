---
type: concept
title: Offer app
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - src/oscar/apps/offer/abstract_models.py
  - src/oscar/apps/offer/conditions.py
  - src/oscar/apps/offer/benefits.py
---

# Offer app

The promotions engine: `ConditionalOffer` pairs a `Condition` (does the
basket qualify?) with a `Benefit` (what discount applies?), each scoped by a
`Range` (which products count).

`Condition` and `Benefit` do **not** use normal Django subclassing for new
types. `AbstractCondition` has a `proxy_class` field (`NullCharField`
storing a dotted import path) and a `proxy_map` property mapping the 3
built-in `type` values (`COUNT`/`VALUE`/`COVERAGE`) to concrete Python
classes (`CountCondition` etc. in `conditions.py`) loaded via
`get_class("offer.conditions", ...)`. A `Condition` row's actual behavior at
runtime comes from instantiating that proxy class over the same DB row, not
from a Django-level subclass — see `add-offer-condition-or-benefit` in
`.agents/skills/` before adding a new condition/benefit type; a naive
`class MyCondition(AbstractCondition)` will NOT be picked up by anything.
