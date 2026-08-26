---
name: close-increment
description: Close an increment or report a change complete — the full suite including the ones that need a container, the format check the build does not perform, verifying by hand what no test reaches, and updating docs/todo.md, docs/specs/ and the decision records. Use before saying anything is done or opening a pull request.
---

# Closing an increment

"It works on my machine" is not a state this list recognises. If a step was skipped, **say which
one** rather than reporting the change as complete.

## 1. The build and the whole suite

```bash
dotnet build            # zero warnings, not "only warnings"
dotnet test             # every project, including the ones needing a container
```

**Zero skipped, zero ignored, zero flaky.** "Tests pass in full" is satisfied by a suite full of
skipped tests, so read the counts rather than the word `Passed`.

The Stop hook runs the build and the fast suite every turn. It does **not** run the
container-backed suites, so this is the first point at which they have been executed.

## 2. `dotnet format --verify-no-changes`

```bash
dotnet format --verify-no-changes
```

A green build is **not** evidence of clean style. Import ordering and whitespace stay below error
level, so a misordered `using` block builds clean and fails here. Two checks, not one — this
repository carried a misordered block from its first commit because somebody assumed otherwise.

## 3. Verify what no test reaches

Enumerate what the suites do not execute, then check those by hand. Anything touching container
orchestration, the identity provider's configuration, the deployment image or startup wiring is in
that set — the `verify-against-running-stack` skill is the procedure.

Write down what you ran and what it answered. A green suite alongside "verified manually" with no
detail is the shape of the three failures that motivated this step.

## 4. Reconcile the rules

Run the `reconcile-rules` skill. Not "update the rules you edited" — hunt for the rule nobody
touched that your change made false.

## 5. Update the record, in the same commit

* **`docs/todo.md`** — the phase rows, and the verified state line: build, test count, format.
* **`docs/specs/NN-*.md`** — for a closing increment: what the plan got wrong, the decisions taken,
  and any finding or limitation this increment closed. The "what the plan got wrong" table is the
  most valuable thing in the log; write it while you still remember being wrong.
* **`docs/adr/`** — a decision that had a real alternative gets a record, and every record says
  what it does **not** authorise. Default to a project record; promoting one later is a file move,
  and retiring a shared one that another project already obeys is an investigation.
* **`docs/backlog.md`** — anything deferred, each entry naming **what would make it due**. An entry
  with no trigger is one nobody can decide against.

## 6. Commits

One logical change each. A schema change ships with its migration; a feature ships with its tests;
a change ships with the documentation it makes false. Messages in the imperative, saying **why**
rather than restating the diff.

A commit that leaves the solution uncompilable is not a commit, whatever the layer order prefers —
and a commit that produces unused code is just as wrong and considerably quieter, because
everything stays green.

## 7. The claim you are about to make

Before saying it is done, ask which sentence in this report is one **nobody checked**. That is the
shape of every expensive mistake in this repository's log: a package approval that was never
needed, an index that existed for one of two features, a realm import that never happened. Each was
believed for increments because it was written down once and never run.
