---
paths:
  - "src/Inventory.Infrastructure/**/*.cs"
  - "tests/Inventory.PersistenceTests/**/*.cs"
---

# Persistence — base

Shared across projects. A deviation from any clause here is recorded under `## Deviations` in
`entity-framework.project.md`, naming the clause it replaces, and that entry wins.

EF Core adapts to the domain, never the other way around. No business rule lives in this layer;
the only thing it is allowed to do with a database failure is **translate** it.

## Configuration

* Every mapping is an `IEntityTypeConfiguration<TEntity>`, `internal sealed`. `OnModelCreating`
  registers them and configures nothing itself.
* No data annotations on entities. The mapping is the configuration's job.
* Identifiers are minted by the application, never by the database: `ValueGeneratedNever()`.
* Value converters are declared **once**, in a converters folder, and reused. Never write the same
  conversion inline twice. Every converter needs a persistence test proving a round trip through
  the real engine preserves the value.
* **Table and column names are declared explicitly** in each configuration — `ToTable` and
  `HasColumnName` — never inferred from the model class name. No naming-convention package: a
  rename in code must not silently rename a column in a database that already holds rows.
* **Column constraints are declared, never left to a provider default.** Maximum length on every
  string, precision and scale on every decimal, required versus optional on every property. A
  money column without precision becomes whatever the provider picks, and a string without a
  length becomes unbounded text — both invisible until the migration is already applied.
* **Relationships are configured explicitly**, and that includes the delete behaviour. **This one
  is load-bearing:** the default for a required foreign key is *cascade*, so a relationship
  written without it makes deleting a parent delete its children. Where the child is an audit
  record, that silently destroys history the domain went to some length to make immutable.
  `Restrict` or `NoAction` unless cascade is what the business actually asked for.
* **A multi-field value object is an owned type**, not an entity with an identity of its own. It
  has no independent existence, so giving it a key and a table invites it to be loaded and saved
  apart from the aggregate that owns it.

## The context stays lightweight

Only `DbSet` properties, model configuration and transaction coordination. "Lightweight" is
enforced rather than hoped for: each concern `SaveChangesAsync` coordinates is a type of its own
beside the context, and the override is **the ordering and nothing else**.

Two symptoms precede the split and are worth recognising: a constant a persistence-wide mechanism
reads ending up on one aggregate's configuration, and a translation branch per aggregate that a new
aggregate forces you to edit. Adding a third responsibility to the override is the same mistake
again.

## Migrations

* Generated with the CLI only. A generated file is never hand-edited.
* Review the `Up` and the `Down` before committing: an unexpected drop or rename means the model
  changed in a way you did not intend.
* Never edit a migration already applied outside your machine — add a new one.
* A migration is committed **together with** the configuration change that produced it.
* Named for what it does. One logical change each.
* Migrations are never applied from the application's startup path —
  [H009](adr/H009-migrations-never-run-at-application-startup.md).

## Repositories and query objects

Repositories expose aggregate roots, express business intent, and never expose an `IQueryable`.
No generic repository. The interface is declared by the application layer; the implementation is
here, and the application layer never sees the context.

Repositories do not save. Persisting is the unit of work's job, so a use case can perform several
operations in one transaction. The context implements it directly — do not build a second
abstraction over it.

A read that needs columns from **more than one aggregate** is a query object, not a repository
method — [H006](adr/H006-query-objects-for-cross-aggregate-reads.md). All of:

* It returns a record declared beside its interface in the application layer, never an aggregate
  and **never a contract record** — this layer cannot see the contracts project, and projecting
  into one would lean on a transitive reference, which is a build accident rather than a decision.
* No `IQueryable`, and it projects only the columns the response carries.
* Nothing writes through it. No add, no update, no tracking.
* Joins are written by hand.

**A paged listing is not by itself a reason for one.** The test is the shape of the **result**, not
how elaborate the `WHERE` becomes: reach for a query object when a response needs a column living
on another aggregate, and for a repository otherwise. A second mechanism where a repository already
answers leaves two ways to read one aggregate, one of them writable.

**An aggregate plus a fact about storing it is still the repository's business.** A pair may carry
a version or a store-owned timestamp; the moment it carries a column belonging to **another**
aggregate it has become a read model and belongs behind a query object. Read literally the rule
above forbids the pair, and it survives because of what it protects: the caller still gets the
whole saveable aggregate, with nothing projected away.

## Reading

* **`AsNoTracking` on every read-only query.** Tracking is for a read whose entity is about to be
  modified, and nothing else. A tracked listing puts a page's worth of aggregates in the change
  tracker for no reason.
* **Filter, sort and page on the server.** Never materialise and then narrow: a `ToList` before a
  `Where` reads the table to return twenty rows, and it is the failure a paged repository is most
  likely to hit. Project only the columns the response carries.
* **No lazy loading**, and no lazy-loading proxies. A hidden query per property access is a
  performance problem that only appears under load.

## Logging

SQL logging is a development affordance. **Sensitive-data logging is never enabled outside
development** — it is one line to turn on and it puts parameter values, which is to say the data
itself, into the log.

## Indexes

Index foreign keys, selectively-filtered columns, sorted columns and identifiers this system
issues.

* **"Frequently filtered" means frequently *and* selectively.** A column with a handful of distinct
  values over a growing table is not worth an index the planner would never choose; serve that
  filter from a composite whose leading column is selective. Record the reasoning where you skip
  one, so the absence reads as a decision.
* **"Business identifier" and "unique" are two claims.** An identifier this system issues can be
  unique; one issued by somebody else — a jurisdiction, a manufacturer — must not be, because a
  duplicate is a data-quality problem for a human and a constraint would refuse a write over a fact
  about the outside world. Ask which of the two you have before adding uniqueness.
* **An index only pays for the comparison the query writes.** A B-tree over text serves equality
  and prefix matching and nothing else; a leading-wildcard match scans past it every time. So
  choosing between an exact filter and a partial one is a persistence decision as much as an API
  one.
* **A value converter removes the choice entirely.** A column persisted through one has the value
  object as its type as far as the provider is concerned, so a pattern match — which takes a string
  — cannot be written against it at all. A partial filter over such a column does not compile into
  SQL. That is a fact about the framework, not a preference; what to do about it is a decision, and
  the appendix names it.

## Domain events

Aggregate roots collect them. Never dispatch from inside a repository or from an entity. Where
dispatch happens relative to the commit is a project decision with real consequences — the
appendix carries it.

## Concurrency

Configure tokens explicitly, and only where an update is **derived from a prior read** —
[H007](adr/H007-optimistic-concurrency-where-an-update-derives-from-a-read.md).
Do not add one to a new table by default: ask the question and **record the answer in the
configuration**, so an absence reads as a decision rather than an oversight.

A translator turns the provider's concurrency failure into the exception the transport answers 409
with. It returns **null** for a failure it does not recognise, and is called from the exception
filter rather than from the body: a `catch` that rethrows resets the stack trace to the rethrowing
line.

## Definition of done for a persistence change

Configuration implemented · migration created and applied · persistence tests pass · indexes
configured · converters round-trip tested · no business logic in this layer.
