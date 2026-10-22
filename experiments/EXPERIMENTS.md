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

## M2 ranking experiments (2026-10-22) — hypotheses disproved

The emission text is a function of the canonical numbering, so the
choice rule is really the numbering rule. Three candidate rules were
tested against the corpus; all fail:

1. **Minimal emission.** Benzene records `c1-2-4-6-5-3-1`; the
   sequential ring numbering would emit `c1-2-3-4-5-6-1`, which is
   lexicographically smaller at the third number. Cyclohexane is the
   same. The oracle does not minimize the emission.
2. **BFS-layer numbering.** Under a valid rank-to-atom mapping, check
   whether ranks are nondecreasing in BFS distance from rank 1. True
   for only 3 of 188 fixtures.
3. **Min/max linear connection table.** The InChI connection table
   for a numbering is: for each canonical rank, the rank followed by
   the ranks of its earlier-numbered neighbours in ascending order.
   Over 139 fixtures with at most 7 atoms, the oracle numbering equals
   the global-minimum table in 24 cases; a 3-atom chain prefers the
   end-first numbering (table `1,2,1,3,2`) over the middle-first
   minimum (`1,2,1,3,1`), while benzene prefers the minimum. No single
   global min/max rule holds.

Conclusion: the numbering is produced by InChI's McKay-style
canonicalization (`CanonGraph` in `ichican2.c`) over the
hydrogen-complete graph, with its exact atom invariants and layered
connection-table comparison. Guessing cannot reproduce it. M2 stage 2
is therefore a source-guided native port of the base ranking path —
`FillOutAtomInvariant2` / `SetInitialRanks2` / `GetCanonRanking2` /
`CtPartFill` / `CtPartCompare` / `CtFullCompare` — with the corpus as
the acceptance test. The IUPAC source (MIT) is read at development
time; no C is compiled, vendored, or called at runtime.

## M2 landed (2026-10-22) — the numbering is the reference's, ported

The source-guided port closed the question this file opened. The
production engine (`inchi-rs#5`) reproduces the oracle's `/c` across
the corpus with three decoded facts that guessing had missed:

1. The base numbering is **hydrogen-free**: invariants are element
   order (carbon first, then other elements by symbol, H last) and
   heavy-atom degree. The acrylonitrile/alkyne fixtures disprove any
   H-count involvement.
2. Ranks are **position-based**: a cell's rank is the position past
   its end, and refinement splits cells by sorted neighbor-rank lists
   scanned from the cell's end (`DifferentiateRanks3`).
3. The `/c` text is a **second DFS over the table**, not a walk over
   the numbering: start at the lowest-degree atom, order neighbors by
   subtree size (closures first), emit `(`,`,`,`)` branch delimiters
   around all but the last child.

Corpus result: green at pin v0.1.1. The one disagreement
(breadth-448, two-bridge symmetric system) is triaged with its decoded
reason. The playground stays as the record of how each rule was
decoded; new decoding work moves into the Rust engine's modules
directly.

## The /c emission grammar (decoded from the corpus)

- Numbers bond to the current walk atom; a fresh number advances the
  walk; a seen number is a ring closure (walk stays).
- `(` pushes the branch point, `)` restores it; after `)` the next
  number bonds to the restored branch point (no `-` required).
- `-` is purely a separator.
