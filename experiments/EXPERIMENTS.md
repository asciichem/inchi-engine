# M2 experiments (the /c connection layer)

Empirical runs against the oracle corpus that drive the emitter
design. Each experiment is a standalone script; results are recorded
here and drive the next step.

## replay-census.rb — is every recorded /c a valid emission of our graph?

Replays each recorded /c token walk on the engine's heavy-atom graph
with backtracking (fresh atoms advance the walk; seen atoms close;
parens branch and restore). Result on the first 120 fixtures:

- 93 with a /c layer checked: **14 uniquely solvable, 79 with
  multiple labelings, 0 unsolvable.**

**0 unsolvable** is the load-bearing result: every recorded /c is a
valid emission of exactly the graph our molfile writer produces —
the writer's connectivity is oracle-exact.

## Open: the emission-choice rule

79/93 emissions are ambiguous (symmetric graphs admit many valid
numberings). The oracle picks one; the emitter must reproduce the
choice. Hypothesis to test next: the recorded emission is the
lexicographically minimal valid emission (numeric-token order) over
all numberings and branch layouts. Testing requires an emitter-grammar
enumerator (full grammar: branches, closures, branch-point
continuations) — the naive flat-token enumeration disproved itself
(closure tokens make the flat sequence a non-preorder).

## The /c emission grammar (decoded from the corpus)

- Numbers bond to the current walk atom; a fresh number advances the
  walk; a seen number is a ring closure (walk stays).
- `(` pushes the branch point, `)` restores it; after `)` the next
  number bonds to the restored branch point (no `-` required).
- `-` is purely a separator.
