# inchi-engine

The reference InChI engine: layer emission driven byte-for-byte by
the oracle corpus in [inchi-tests](https://github.com/asciichem/inchi-tests).
The [Rust port](https://github.com/asciichem/inchi-rs) passes the
same suite. MIT.

```sh
ruby gate.rb ../inchi-tests/corpus/fixtures/identity.json
```
