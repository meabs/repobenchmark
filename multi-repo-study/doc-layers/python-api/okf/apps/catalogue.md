---
type: concept
title: Catalogue app
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28
sources:
  - src/oscar/apps/catalogue/abstract_models.py
  - src/oscar/apps/catalogue/models.py
  - src/oscar/apps/catalogue/migrations
---

# Catalogue app

Defines the product data model: `ProductClass`, `Category` (a `treebeard`
`MP_Node`, i.e. a materialized-path tree, not a plain FK tree),
`ProductCategory`, `Product`, `ProductRecommendation`, `ProductAttribute` +
`ProductAttributeValue` (Oscar's EAV-style arbitrary product attributes),
`AttributeOptionGroup`/`AttributeOption`, `Option`, `ProductImage`,
`ProductCategoryHierarchy`.

All of these follow the abstract/concrete split described in
[loading-and-overrides.md](loading-and-overrides.md) — see `add-model-field`
in `.agents/skills/` for how to add a field to one.

`src/oscar/apps/catalogue/migrations/` is at `0032` as of this bundle's
generation (`0032_category_exclude_from_menu_category_long_description.py`) —
check the actual highest-numbered file before adding a new one, this number
will drift.
