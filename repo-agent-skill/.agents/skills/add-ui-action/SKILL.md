---
name: add-ui-action
description: Add a UI action (button/menu item) to an existing table or list page in this repo's frontend, such as Items — the mutation/toast/cache-invalidation pattern to follow, and how to wire in filters.
---

# Add a UI action to an existing table/list page (e.g. Items)

Follow the pattern already used by `EditItem`/`DeleteItem` in
`frontend/src/components/Items/`:

1. A component using `useMutation` (from `@tanstack/react-query`) calling the
   generated client (`ItemsService.xxx`), with `onSuccess` showing a toast via
   `useCustomToast` and `onSettled` invalidating the `["items"]` query key so the
   table refetches.
2. Wire it into `ItemActionsMenu.tsx`'s dropdown alongside the existing actions.
3. If the change affects what's shown in the table (e.g. a new visual state), update
   `columns.tsx` — check for an existing UI primitive first
   (`frontend/src/components/ui/`) before adding a new one.
4. If the list should be filterable, add the toggle/control in the route file under
   `frontend/src/routes/_layout/` following whatever pattern nearby controls (like
   `AddItem`) already use, and thread the filter state into the query's `queryKey`
   so cached results don't leak across filter states.

Requires the generated client to already expose whatever endpoint you're calling —
see the `add-api-endpoint` and `regenerate-frontend-client` skills if it doesn't yet.
When you're done, see the `verify-work` skill before calling it complete.
