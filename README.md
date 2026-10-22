# inchi-engine

An exploration playground used to decode the InChI ruleset from the
oracle corpus before implementing them in
[inchi-rs](https://github.com/asciichem/inchi-rs), the production
engine. It is not a reference implementation and is not maintained
as a shipping artifact.

What lives here:

- `lib/inchi/engine.rb` — the early formula-layer rules (Hill order,
  implicit H, ±1 proton standardization), kept as executable notes.
- `lib/inchi/clayer.rb` — the decoded `/c` emission grammar (walk,
  branch, closure).
- `gate.rb` — the same kind-matched oracle gate the Rust engine runs.
- `experiments/` — replay census and ranking experiments, with their
  findings in `EXPERIMENTS.md`.

```sh
ruby gate.rb ../inchi-tests/corpus/fixtures/identity.json
```

MIT.
