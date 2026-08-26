# dotnet-house

The portable half of a .NET solution's context: rules, decisions, procedures and a build gate,
kept in one repository so that a rule and the skill depending on it never arrive in a consuming
project at different times.

**This is v0.** Everything here has been seen to work in exactly one project. Nothing is stable
until a second one consumes it — see [Exit criterion](#exit-criterion-for-v0).

## What is in here

| | |
|---|---|
| `*.md` at the root | The six rule bases. They talk about **roles** — Api, Application, Domain, Contracts, Infrastructure — never about project names |
| `adr/` | `H###`: decisions that can be dated as doctrine **before** any one project. Each names what sustains it outside this repository, and what it does **not** authorise |
| `skills/` | Four procedures: `feature-workflow`, `close-increment`, `reconcile-rules`, `ef-migration` |
| `agents/` | `rules-reviewer` hunts the rule a change made false; `repo-explorer` answers a question from the four layers that hold the reasoning. Both **report by path** — they write a file and reply with its name, so delegating costs the caller a line instead of a transcript |
| `hooks/` | `stop-gate.ps1` formats what changed, builds, runs the test projects that need no container, and refuses to end the turn if either fails. `session-doctor.ps1` checks at session start what a suite would otherwise discover three minutes in — the SDK, a container daemon, the environment file — and never blocks. Nothing about any repository is written in either: every target is discovered |
| `templates/` | A `CLAUDE.md` skeleton to fill in rather than start from nothing |
| `.claude-plugin/` | `plugin.json`, the manifest; `marketplace.json`, so the package can be installed rather than only read |

## How a project consumes it

**Two halves, and only one of them can be a package.**

The skills, the agents and the hooks arrive by installing the plugin. In the consumer's
`.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "dotnet-house": { "source": { "source": "github", "repo": "Guillervazio/dotnet-house" } }
  },
  "enabledPlugins": { "dotnet-house@dotnet-house": true }
}
```

The marketplace is added when the folder is trusted, with no separate prompt. A consumer that
already keeps hand copies of those files **deletes them once the plugin loads** — two skills with
one name is not a fallback, it is an ambiguity.

The rules cannot travel that way. There is no `rules` field in a plugin manifest, so they have to
end up **inside** the consuming repository's `.claude/rules/shared/`, which is where they are
loaded from. Copy them, and rewrite the `adr/H###` links to wherever that project keeps its copy of
the records. That copy is the drift this repository has not yet closed; it is the open problem, not
a design.


### The one thing every consumer edits

Each base opens with a `paths:` block, and **two of them name project files**:

```yaml
# api-guidelines.md
paths:
  - "src/Inventory.Api/**/*.cs"          # <- your API project
  - "src/Inventory.Contracts/**/*.cs"
  - "tests/Inventory.IntegrationTests/**/*.cs"
  - "tests/Inventory.ScenarioTests/**/*.cs"

# entity-framework.md
paths:
  - "src/Inventory.Infrastructure/**/*.cs"
  - "tests/Inventory.PersistenceTests/**/*.cs"
```

They are left as the originating project's names on purpose, as a worked example rather than a
placeholder nobody has run. **Adapting them is not a deviation**: `paths:` decides *when* a rule
loads, not *what* it requires, so changing it touches no clause and needs no decision record. The
other four bases are already generic — `**/*.cs`, `src/**/*.cs`, `tests/**/*.cs`, `**/*.csproj` —
and need nothing.

A wildcard form, `src/*.Infrastructure/**/*.cs`, would remove even this step. It is **not shipped,
because it has not been verified to match.** A rule whose `paths:` silently matches nothing is
invisible, which is the worst failure mode a rule has, so it stays out until somebody confirms it
in a fresh session.

Each area is then two files in the consumer:

* `shared/<area>.md` — from here. **Never edited from inside a consuming project.**
* `<area>.project.md` — the consumer's own: role-to-project mapping, concrete names, and the
  tables the base declares it must fill.

A change to a base is a commit **here**, and reaches the others when they update.

## Deviating from a base

Under `## Deviations` in that area's appendix, naming the clause it replaces — and that entry
wins. There is no mechanical precedence between two project-scoped rules, so it is declared rather
than assumed. **A deviation without a project decision record is not a deviation, it is drift.**

## Promotion and demotion

The default for a new decision is **P**, in the consuming project.

* **P → H** when a **second** project takes the same decision independently, without copying it.
  Cheap: move the file, delete the two appendix entries, leave a pointer in each project.
* **H → P** when **two** projects need to deviate, or one needs to deviate and the other never
  exercised it. Deliberately expensive: enumerate who obeys it today, decide for each whether its
  code **depends** on the base or merely coincides with it, and record the ones that keep following
  it. One deviation is what `## Deviations` exists to absorb.

Promoting is a file move. Demoting is an investigation. That asymmetry is the whole argument for
the default.

### What was born here instead of promoted

`agents/` and `session-doctor.ps1` did not arrive through that door. They were written here first,
with one project consuming the package and none having taken the decision independently — which is
exactly what the default above exists to prevent.

The easy excuse is false and worth refusing in writing: a project **can** hold `.claude/agents/`
and its own hooks, so the P form existed and was not used. What was chosen instead was reach — an
artefact that only ever exists in one repository teaches that repository nothing about whether it
is portable, and these three are the first things here whose portability the discovery logic can
actually be tested on.

The debt is recorded rather than paid: until a second project exercises them, they carry **less**
evidence than every other file here, not the same amount. The exit criterion below is where that
gets settled.

## Exit criterion for v0

This package is **v1** when a project B, in another domain, closes **two complete increments**
consuming it, and at the end of the second:

* it deviated from **at most one** base clause, recorded as a project decision record;
* it never had to edit a base from inside its own repository;
* the Stop hook ran in B **without** a `stop-gate.config.json` — the discovery got it right alone;
* the session doctor ran in B **without** a `session-doctor.config.json`, and its verdict on B's
  container requirement matched what B's suites actually needed;
* both agents were invoked in B at least once, and the reviewer's findings there cited B's own
  appendix rather than the base — an agent that only ever quotes the portable half has not been
  shown to read the half that varies;
* the mandatory tables in `testing` and `build-and-packages` are complete by their own stated
  condition.

If B needs to deviate from two or more, those bases were project decisions in disguise, and they
are demoted before v1 is declared.
