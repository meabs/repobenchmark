---
name: add-form-with-validation
description: Add a form backed by a Zod schema and the repo's Form/Input/Textarea wrapper components — how validation, submit, and error display are wired, using create-discussion.tsx as the reference.
---

# Add a form with validation

1. Define the input schema with Zod next to the mutation it submits to (e.g.
   `createDiscussionInputSchema` in `src/features/discussions/api/create-discussion.ts`),
   and export `type X = z.infer<typeof schemaX>` from the same file — don't define a
   separate, hand-written TS type for form data.
2. Use `Form` from `@/components/ui/form` (not a raw `<form>` or bare
   `react-hook-form`), passing `schema={yourInputSchema}` — it wires
   `zodResolver` and gives you `register`/`formState` in its render-prop children.
3. Use the existing field components (`Input`, `Textarea` from `@/components/ui/form`)
   with `error={formState.errors['fieldName']}` and
   `registration={register('fieldName')}` — this is the only pattern used in the
   repo for wiring RHF registration + Zod error display; don't hand-roll error
   rendering.
4. On submit, call the mutation's `.mutate({ data: values })` inside the `Form`'s
   `onSubmit` prop (values are already validated and typed at this point).
5. For a create/edit form presented in a drawer (the repo's convention for
   create/update forms, see `create-discussion.tsx` and `update-discussion.tsx`),
   wrap the `Form` in `FormDrawer` from `@/components/ui/form`, passing
   `isDone={mutation.isSuccess}` and a `submitButton` with
   `form="<same id as the Form>"` so the drawer's external submit button triggers
   the form.
6. On success, call `addNotification({ type: 'success', title: '...' })` from
   `useNotifications` (`@/components/ui/notifications`) — this is how the repo
   surfaces success feedback everywhere; errors are already handled globally by
   `api-client.ts`'s response interceptor, don't add your own error notification.
