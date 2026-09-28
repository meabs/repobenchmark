---
type: concept
title: Vet / Specialty
generated:
  by: reference_agent/claude-sonnet-5
  at: 2026-09-28T09:39:22Z
sources:
  - src/main/java/org/springframework/samples/petclinic/vet/Vet.java
  - src/main/resources/db/h2/schema.sql
---

# Vet / Specialty

`Vet` extends `Person` (first/last name only — no address/phone, unlike `Owner`) and
has a `@ManyToMany(fetch = EAGER) Set<Specialty>` through the join table
`vet_specialties` (`vet_id`, `specialty_id`, no own primary key). `getSpecialties()`
is the public accessor and always returns a *sorted-by-name* `List`, computed on
each call from the internal `Set` — there is no persisted ordering, so don't assume
`Vet.specialties` insertion order means anything.

`Vet` carries an `@XmlElement` on `getSpecialties()` — this is a JAXB leftover for
the `/vets` endpoint (`VetController.showResourcesVetList`, wrapped in a `Vets`
holder object) which is returned as `@ResponseBody`, serialized to JSON via Jackson
in practice, not XML; the `@XmlElement` annotation is currently inert for that path.
