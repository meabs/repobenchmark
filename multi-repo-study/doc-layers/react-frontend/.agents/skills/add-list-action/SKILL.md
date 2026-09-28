---
name: add-list-action
description: Add a row-level action (a button in a Table column, like the existing delete/view actions on the discussions list) to an existing list/table screen.
---

# Add a row-level action to an existing list

Reference: `src/features/discussions/components/discussions-list.tsx` and
`delete-discussion.tsx`.

1. The list itself is a `Table` from `@/components/ui/table` given a `columns` array;
   each column is `{ title, field, Cell? }`. A trailing action column has an empty
   `title`, reuses the row's id `field`, and renders its control from `Cell({ entry })`.
   Add a new column entry rather than modifying an existing `Cell`.
2. For an action that mutates data (delete, and by the same pattern any new toggle
   action), put it in its own small component (see `delete-discussion.tsx`) that
   owns its mutation hook and any confirmation UI — don't inline mutation logic in
   the `Cell` callback.
3. If the action should invalidate the list after it runs, do this in the mutation's
   `onSuccess` via `queryClient.invalidateQueries({ queryKey:
   getDiscussionsQueryOptions().queryKey })` — matches every other mutation in this
   feature (see `create-discussion.ts`).
4. If the action is role-gated, wrap the rendered control in `<Authorization
   allowedRoles={[ROLES.ADMIN]}>` (see `create-discussion.tsx`) — column `Cell`
   functions are plain components, they can use hooks and this wrapper directly.
5. See `write-component-test` for how to cover the new action.
