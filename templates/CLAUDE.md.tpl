# CLAUDE.md

<One or two lines: what this system is for, in business terms. Not deducible from the code.>

---

## Commands

```bash
dotnet build
dotnet test
dotnet format

dotnet test tests/<Project>/<Project>.csproj      # the fast one, no container needed
dotnet test --filter "FullyQualifiedName~<Name>"
dotnet run --project src/<Api>/<Api>.csproj
```

<Which suites need a container runtime, and that it must be running. Without this line, a failing
test suite says nothing about why.>

<The exact test project names, if CI refers to them.>

---

## Dependency direction

Never violate it. Draw **your** graph here, not this one — the five-role shape below is one
solution's answer, kept as a worked example. A three-project service with three surfaces over one
core is as valid, and `architecture.md` requires only that the graph be written down, that the
forbidden edges be named as edges, and that any edge which is not a leaf pointing at the core carry
its reason.

```
Api → Application → Domain
Api → Infrastructure → Application → Domain
Api → Contracts ← Application
Domain → (nothing)
```

Forbidden: `Domain → Infrastructure`, `Domain → Application`, `Application → Infrastructure`.

---

## Settled

<Target framework.> **No new NuGet package without explicit approval** — approved, rejected and
pinned are listed in the `build-and-packages` appendix.

<Anything else settled, as a one-line list pointing at the decision records. Do not restate the
argument here; that is what the records are for.>

---

## Where the binding specifications live

`.claude/rules/`, loaded automatically when a matching file is read, and binding whether or not
they are quoted back. Each area is two files sharing one `paths:` — `shared/<area>.md` is the
portable base, `<area>.project.md` is this repository's appendix. A deviation from a base clause
goes under `## Deviations` in that appendix, naming the clause it replaces, and **that entry
wins**.

Each fact has one home; a rule that needs a fact from elsewhere links to it rather than restating
it. The long reasoning lives in the decision records, read on demand.

---

## Working here

* Starting a change is the `feature-workflow` skill; finishing one is `close-increment`.
* Branches are `feature/…`, `docs/…` or `refactor/…`, and commit messages are in the imperative
  and say **why**.
* **No new architectural patterns.** Reuse what already exists.
* No TODOs, no commented-out code, no placeholders.
* If a requirement is ambiguous or several designs are defensible, ask before choosing.
