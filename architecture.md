---
paths:
  - "src/**/*.cs"
  - "tests/**/*.cs"
---

# Architecture — base

Shared across projects. A deviation from any clause here is recorded under `## Deviations` in
`architecture.project.md`, naming the clause it replaces, and that entry wins.

Clean Architecture, lightweight DDD, vertical slices inside the application layer, one deployable
unit. Layers are the only structural boundary; this is not a modular monolith.

## Dependency direction

Roles, not project names — the appendix maps them:

```
Api → Application → Domain
Api → Infrastructure → Application → Domain
Api → Contracts ← Application
Domain → nothing        Contracts → nothing
```

Forbidden outright: `Domain → Application`, `Domain → Infrastructure`, `Domain → Contracts`,
`Application → Infrastructure`, `Contracts → anything`.

The Api references Infrastructure **only** to register implementations at startup. No endpoint may
use an Infrastructure type directly.

A test project references only what it exercises. Needing Infrastructure inside a unit test suite
means the test is not a unit test — not that the reference is missing.

## What each role must not contain

* **Domain** — no framework of any kind, no packages beyond the base class library, no application
  logic. An aggregate that knows about repositories has stopped being a domain model.
* **Application** — no persistence implementations, no HTTP concerns: no request context, no status
  codes, no action results. A handler that knows it is being called over HTTP cannot be reused by
  anything that is not.
* **Contracts** — records only. No behaviour, no domain types, no validation attributes. See
  [H004](adr/H004-separate-contracts-project.md).
* **Api** — no business rules, no direct database access. A controller binds the request, calls one
  handler, maps the result.

Application and Infrastructure each expose registration as a single extension method.

## Which layer implements an abstraction

The layer that already owns the dependency the abstraction hides —
[H003](adr/H003-which-layer-implements-an-abstraction.md). For anything
reaching a database or a third party that is Infrastructure, and that is the overwhelming
majority. Where it is not, the appendix names the case.

## Vertical slices

* One folder per use case, one handler per folder, grouped by business area.
* A slice never calls another slice's handler. Shared behaviour moves **down** into a domain
  service or an application abstraction, never sideways.
* Promote code out of a slice only when a second slice genuinely needs it. Duplication across two
  slices is cheaper than a premature abstraction.

## Command and query handling

Handlers are plain services injected where they are used: no mediator, no dispatcher, no
reflection-based resolution. If an endpoint needs several handlers, it injects several handlers.

* Commands and queries are records. Commands mutate; queries never do.
* Handlers are `sealed` and scoped.
* Cross-cutting concerns are DI decorators around a specific closed handler interface, never a
  hidden global pipeline.
