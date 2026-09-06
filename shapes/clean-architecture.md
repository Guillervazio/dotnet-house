# Clean Architecture — a shape, not a base

**This is not a rule base and nothing inherits it.** It was `architecture.md` until the second
project to consume this package would have had to deviate from five of its clauses, which by the
[exit criterion](../README.md#exit-criterion-for-v0) means it was a project decision wearing a
base's clothes. It was demoted rather than deleted: the first consumer depends on every word of it,
and a third may want the same shape.

**Do not copy this file into `.claude/rules/`.** It deliberately carries no `paths:`, and a rule
file without one loads into every session unconditionally. A project adopting this shape copies the
clauses it adopts into its own `architecture.project.md`, where they become that project's rules
and can be changed without asking anybody. What stays binding for every consumer is the thin
[architecture.md](../architecture.md), and nothing here overrides it.

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
* **Contracts** — records only. No behaviour, no domain types, no validation attributes, and **no
  framework at all** beyond serialisation attributes. A binding attribute or a documentation
  package here couples every client that consumes the contracts to this API's web stack. See
  [H004](../adr/H004-separate-contracts-project.md).
* **Infrastructure** — **no business rules.** It implements the abstractions whose concrete
  dependency it owns, and the only thing it may do with a failure from a third party is translate
  it.
* **Api** — no business rules, no direct database access. A controller binds the request, calls one
  handler, maps the result.

Application and Infrastructure each expose registration as a single extension method.

## Persistence abstractions, declared here and implemented elsewhere

The interfaces live in Application, so this is where the rule has to be stated — the persistence
rules load for the implementing project, and by then the interface is already written.

Repositories expose **aggregate roots**, never an `IQueryable`. A read that spans aggregates is a
query object rather than a repository method —
[H006](../adr/H006-query-objects-for-cross-aggregate-reads.md).

## Which layer implements an abstraction

The layer that already owns the dependency the abstraction hides —
[H003](../adr/H003-which-layer-implements-an-abstraction.md). For anything
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
