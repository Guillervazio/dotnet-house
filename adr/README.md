# House ADRs

Decisions that can be dated as doctrine **before** this project: each one names what sustains it
outside this repository. They are the portable half of the collection — the project's own
decisions are in [../](../), numbered `P###`.

They live here until the `dotnet-house` package is extracted, at which point this folder moves
there whole and this repository keeps pointers. Nothing about them is specific to Plastipack; if
one turns out to be, it is despromoted to a `P###` by the rule in the restructure plan.

The default for a new decision is `P`. A `P` is promoted here only when a **second** project takes
it independently, which is a file move. Removing an `H` that another project already obeys is an
investigation, and that asymmetry is why the default is `P`.
