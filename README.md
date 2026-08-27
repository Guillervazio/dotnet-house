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
| `agents/` | `rules-reviewer` hunts the rule a change made false; `repo-explorer` answers a question from the four layers that hold the reasoning. Both are **told to report by path** — write a file, reply with its name. Read that as an intention, not a behaviour: [it has been observed not to happen](#the-path-contract-is-not-holding) |
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

That deletion matters most for a hook, for a reason a skill does not have: **a hook that cannot
find its script does not fail loudly.** The harness reports it with a non-blocking status code, the
turn ends normally, and nothing on screen says the gate did not run. So while a consumer still
keeps a copy declared in its own `.claude/settings.json`, write that command's path **relative** to
the repository root — `.claude\hooks\stop-gate.ps1`. `$CLAUDE_PROJECT_DIR` is **not** substituted
there: it reaches the shell verbatim, resolves to nothing, and the entry silently points at a file
that does not exist. Only `${CLAUDE_PLUGIN_ROOT}`, inside a plugin's own `hooks.json`, is expanded
by the harness. This is not hypothetical — it is how the originating project came to believe it had
two gates while it had one, for as long as the copy was kept.

The general rule that episode paid for, worth applying to anything here that runs rather than gets
read: **a gate counts only from the moment it has been seen blocking, and a copy nobody runs is
worse than no copy, because it gets counted.** Neither hook announces itself. A `SessionStart`'s
output is rendered in no client — it goes into the model's context — and a failing `Stop` hook
writes where nobody looks, so **"I saw nothing" is not evidence in either direction.** The way to
find out is to ask the session what it was told, and to break the build on purpose and watch the
block counter under `%TEMP%\claude-stop-gate\`. Do that once per consuming project. Verified to
exist is not verified to fire, and the distinction is invisible by construction.

**Every change here needs the `version` in `plugin.json` bumped, including a change to prose.** The
installed copy is cached per version, so `claude plugin marketplace update` refreshes the clone and
leaves the cache untouched, and `claude plugin update` then answers *"already at the latest version
(0.2.0)"* and does nothing. Merging to `master` is therefore **not** shipping: with the version
unmoved a consumer keeps running the old package, is told its plugin is up to date, and has no way
to notice — the same silent staleness as the hook above, one layer out. This paragraph exists
because that is exactly what happened to the commit immediately before it.

**A bumped version also ships exactly once.** A second change merged under a number the cache has
already taken is hidden *better* than the first, because the answer improves while staying wrong:
`claude plugin update` now reports *"already at the latest version (0.2.1)"* — the number you
expected — while serving the content of whichever merge reached that number first. Neither the
marketplace clone nor the CLI can tell you this. The only thing that can is the cache itself:

```bash
ls ~/.claude/plugins/cache/<marketplace>/<plugin>/     # one directory per version taken
grep -r "the sentence you just changed" ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/
```

So the version moves **per merge**, not per branch. This paragraph, too, exists because of the
commit immediately before it: 0.2.1 was merged and cached, and a correction pushed to the same
branch afterwards was merged under the same number and never reached the one consumer there is.

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

### The path contract is not holding

The originating project invoked both agents for the first time on 27 August 2026, and **neither
wrote a file and neither replied with a path.** Both dumped their findings into the caller's
context, and both said why: the harness tells a subagent that its final text *is* its return value,
and that instruction outranks anything a definition says. `Your answer is a path` is currently
losing that argument twice out of two.

What it cost, measured on that run: 31k and 58k subagent tokens spent to deliver roughly 2.5k and
3k of transcript into the caller — which is precisely the saving the path was invented to make. The
answers themselves were good, so the delegation is still worth doing; what is not established is
that it is **cheap**, and cheapness was the whole argument for the contract.

This is left as written intention rather than repaired, because the two available repairs are worse
than the finding. Hardening the wording is a guess at whether a stronger instruction outranks the
harness's, and would need re-measuring to mean anything. Deleting the contract throws away the one
idea `agents/` was built around before knowing whether the harness will keep behaving this way.
What remains true and observed is the other delta: these two know **which of the four layers
answers which question**, and the built-in `Explore` does not.

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
* each of them replied with a **path** rather than with its findings, or the contract was dropped
  from the definitions before v1 — the originating project observed neither doing so, and a
  promise the package cannot keep must not survive into a stable version;
* the mandatory tables in `testing` and `build-and-packages` are complete by their own stated
  condition.

If B needs to deviate from two or more, those bases were project decisions in disguise, and they
are demoted before v1 is declared.
