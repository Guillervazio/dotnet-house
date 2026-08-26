---
paths:
  - "**/*.cs"
---

# Coding conventions — base

Shared across projects. A deviation from any clause here is recorded under `## Deviations` in
`coding-conventions.project.md`, naming the clause it replaces, and that entry wins. A deviation
without a project ADR is not a deviation, it is drift.

## What the toolchain already enforces, and what it does not

`.editorconfig` plus `EnforceCodeStyleInBuild` and `TreatWarningsAsErrors` **fail the build** on:
explicit types over `var`, braces on every block, explicit access modifiers, file-scoped
namespaces, `using` outside the namespace, unmarked `readonly` fields, naming, and nullable
violations. None of that is written down again here — the compiler says it louder and sooner.

Four more are corrected by `dotnet format` and **not** by the build: `using` order, whitespace,
redundant `this.`, and `System.Int32` for `int`. They are enforced only because the Stop hook runs
`dotnet format` every turn. **If that hook is removed, they stop being enforced by anything.**

One convention nothing checks: an asynchronous method ends with the `Async` suffix.

## Time

`DateTimeOffset` always. Never `DateTime`, `DateTime.Now` or `DateTime.UtcNow`. The current time
comes from an injected `TimeProvider`, which is what makes it substitutable in a test. `DateOnly`
and `TimeOnly` where the value genuinely has no time-zone dimension.

## Domain models

* Aggregates and entities: classes with private setters and behaviour-bearing methods.
* Value objects: records — see [H001](adr/H001-no-value-object-base-type.md).
* Identifiers: strongly typed, never a bare primitive.
* Construction: a static factory that enforces the invariants, not a public constructor.
* Types not designed for inheritance are `sealed`. That is the default, not the exception.
* Contract records expose primitives, never domain types.

## Missing versus refused

A query handler returns `null` for a resource that does not exist and the transport turns that
into a 404. A command handler on a missing resource throws, because it cannot fulfil its contract.
Do not use an exception for the query case.

## Nullability

Never suppress a warning with `!` unless it is provably safe, and write the reason in a comment
where you do.

## Cancellation

Every method that performs I/O takes a `CancellationToken` and passes it down. No analyser enforces
this by default.

## Static classes

A static class is justified when there is nothing an instance would hold: an extension container,
a registration class, or a compile-time constant table plus the lookups that read it.

The boundary is the part worth stating. A type that acquires a dependency, or holds a value that
varies per request or per environment, has left this case and is a scoped service. Configuration
read at startup is the tempting mistake — it is not a constant, it only looks like one from inside
the method reading it.

## Comments

Comments explain **why**, never **what**. A comment restating the code is noise. No commented-out
code, and no `TODO`: what is deferred is recorded outside the code, and the project appendix says
where.
