---
name: ef-migration
description: Create and review an EF Core migration — how to find the migrations project and the startup project rather than hard-coding them, the naming convention, what to look for in the generated Up and Down before committing, and why the migration belongs in the same commit as the configuration that produced it. Use whenever the database schema changes.
---

# Adding an EF Core migration

## 1. Find the two projects, do not assume them

Two arguments are needed and both are discoverable:

* **The migrations project** is the one referencing `Microsoft.EntityFrameworkCore.Design`.
* **The startup project** is the one using the `Microsoft.NET.Sdk.Web` SDK.

```bash
grep -rl "EntityFrameworkCore.Design" --include=*.csproj .
grep -rl "Microsoft.NET.Sdk.Web" --include=*.csproj .
```

If either returns more than one result, ask rather than picking. The exact command line for this
repository is in `CLAUDE.md`, and it is worth reading before typing it from memory.

## 2. Name it for what it does

`AddSupplierTaxIdIndex`, `CreateInventoryMovementsTable`, `AddReorderPointAndNotifications`.
Never `Migration1`, `Update`, `Changes` or `Fix`.

One logical change per migration — with one exception worth knowing in advance: **the tool
generates one diff per invocation, not one per intention.** If the model changed in two ways since
the last migration, the first `migrations add` carries both. Splitting them afterwards means
editing the model to hide half of it, generating, and putting it back — three chances to commit a
wrong snapshot in exchange for two migrations nobody will ever apply separately. Name the one
migration for what it actually does.

## 3. Review `Up` **and** `Down` before committing

This is the step that gets skipped, and it is the only one that catches the expensive mistake.

* An unexpected `DropColumn` or `RenameColumn` means the model changed in a way you did not intend
  — most often a property renamed in code against a column that already holds rows.
* A `CreateTable` you did not expect means a type got picked up as an entity.
* A `Down` that does not reverse the `Up` means the migration is not safely revertible.

Then apply it against a real database and run the persistence suite.

## 4. Two rules with no exceptions

* **Never hand-edit a generated migration file.** If it is wrong, fix the model and regenerate.
* **Never edit a migration already applied outside your machine.** Add a new one.

## 5. It ships with the configuration that produced it

The migration and the entity configuration change go in the **same commit**. A commit containing
one without the other is a commit that does not describe a working state of the schema.

If the deployment path builds a migration bundle with a pinned tool version, that pin moves with
the ORM packages — it compiles the bundle against the design-time package, so a version skew there
fails at deploy time and not in any test.
