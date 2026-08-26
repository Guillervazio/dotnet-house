---
name: feature-workflow
description: The order of work for a feature — which layer to build in which order and why that order, how to ask for a NuGet package approval, and where a commit boundary goes. Use when starting any feature, use case or endpoint, or when asked to add a package. Finishing one is the close-increment skill.
---

# Working order for a feature

## Before writing code

1. Understand the business requirement. If it is ambiguous, **ask** — do not guess.
2. Identify the affected layers.
3. Look for an existing abstraction or pattern before creating one.
4. Decide the smallest correct change.

Modifying existing code beats introducing a new abstraction. A new pattern needs a reason that
survives being written down.

## The order, and why it is this order

Each step constrains the next. Working outside-in leaks HTTP concerns into the domain.

1. **Define the use case.** One command or query, one handler.
2. **Identify the business rules.** Which belong in the aggregate, which are shape validation.
3. **Write the tests first** where the behaviour is already clear — domain rules especially.
4. **Domain**: entities, value objects, invariants, domain events.
5. **Application**: the command or query record, the handler, the validator, any abstraction it
   needs.
6. **Infrastructure**: repository implementation, entity configuration, value converters.
7. **Contracts**: request and response records.
8. **API**: the controller action, `[ProducesResponseType]` per status code, authorization — a
   named policy in almost every case, and a row filter read from the token in the rare one a policy
   cannot express. The default is the policy.
9. **Migration**, if the schema changed — the `ef-migration` skill.
10. Finish with the `close-increment` skill.

Standing a layer up from nothing inverts 5 and 7: handlers return contract records, so Contracts
has to compile before Application does.

## Where a commit boundary can and cannot go

The layer order is not a commit order. Two constraints override it, and this repository learned
each of them separately:

* **A commit may not leave the solution uncompilable.** If startup validates the service graph, a
  handler registered without the implementation it depends on fails every end-to-end test — so the
  slice and its persistence mapping are one commit whatever the layer order prefers.
* **A commit may not produce unused code.** An abstraction with no reader is dead code, and unlike
  the case above **nothing fails**: the build stays green and the tests stay green, so the only
  thing between that commit and the repository is somebody noticing.

A refactor that shares a commit with a feature makes a failure ambiguous about which half caused
it. Split those, and prove a pure refactor with the tests that already exist.

## Adding a package

Packages are never added silently.

1. Check the approved and rejected lists in your project's `build-and-packages` appendix — it may
   already be decided either way.
2. **Check whether the framework already covers it, by compiling rather than by reading.** This is
   the step that has been skipped twice here: health checks and CORS were both believed to need a
   package, and neither did. A claim about what a dependency costs is a claim.
3. Ask for approval, stating what it does and why nothing already approved suffices.
4. Add it to `Directory.Packages.props`, reference it from the **one** project that needs it, and
   record it in the `build-and-packages` appendix in the same change.

## Adding a rule instead

If what the change decided is a rule rather than a feature, the reconciliation is the
`reconcile-rules` skill — and it applies to every change, not only to this kind.
