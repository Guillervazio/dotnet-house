---
name: reconcile-rules
description: Find the rule a change just made false. How to name what was decided, how to grep for the assertion rather than for the feature name, how to check whether the claim is repeated, and how to rewrite a rule so it says what it does not authorise. Use after any change that decided something the rules did not anticipate, before reporting the change complete.
---

# Reconciling the rules with what you just built

The rules are what the next agent reads before it reads any code. A rule a change made false is
**worse than no rule**: it will be followed, and it will undo the decision.

This is not "update the rules you edited". The case that gets missed is the opposite one — a rule
**nobody touched**, quietly contradicted by code somebody wrote. It has to be hunted, not noticed.

## 1. Name what the change decided

Not what it added — what it **decided**. The candidates are shaped like this:

* A layer doing something it did not do before.
* A folder holding a kind of file it did not hold before.
* An abstraction implemented somewhere unusual.
* A rule read literally forbidding what you just did, or demanding something that turned out to be
  impossible.
* A number, a threshold or a default that nothing else in the repository names.

If nothing on that list fits, the change probably decided nothing and this is quick. Say so rather
than skipping it silently.

## 2. Grep for the assertion, not for the feature name

The rule that is now wrong almost never mentions your feature. It states a general claim that your
change made false.

```bash
grep -rn "implements interfaces" .claude/rules/     # right: the claim
grep -rn "ICurrentUser" .claude/rules/              # wrong: the feature
```

Write out the sentence you believe is now false, then search for **its** words.

## 3. Check whether the claim is repeated

Layer responsibilities, folder conventions and package ownership tend to appear in more than one
file. Fixing one copy leaves the other to be believed — and the stale copy is the one somebody
reads. Grep for the claim, not for the file you already opened.

Count what you find before editing anything. If a claim appears three times, three edits.

## 4. Rewrite the rule to state the decision **and its boundary**

A rule that records an exception without saying what it does not authorise invites the exception
to spread to every case that is easier to write that way.

Every rewritten rule answers two questions:

* What is now true?
* What does this **not** license?

The second is the one that gets skipped, and it is the one that pays.

## 5. Recording it elsewhere does not discharge this

A rationale in a README or a decision record is worth writing, and it leaves the rules asserting
the opposite to whoever reads them next. Both, or the rules win by default.

## Where long reasoning goes instead

If what you are about to write is three paragraphs of argument, it is not a rule — it is a
decision record. Write it as one, and leave the rule as the short binding statement with a link.
A rule nobody finishes reading is a rule nobody follows.
