# Repository Guidelines

## Layout

One Scarb workspace (root `Scarb.toml`) with five packages: `core/midi` (library: MIDI types,
interfaces, SMF writing, packing), `core/midi_contracts` (MidiSoundPage, ScaleMidiProvider),
`beasts/beast_composer` (library: the Beast Sound composer), `beasts/beast_composer/inputs`
(canonical musical inputs and codecs), and `beasts/beast_contracts` (BeastMidiProvider,
BeastSoundComposer). `bench/` is a separate Scarb workspace, the gas benchmark.
`offchain/beast-sound/` is the JS reference engine and the generators of three Cairo files
(`TESTING.md`). See `README.md` for details.

## Toolchain

scarb 2.21.0 and Starknet Foundry 0.64.1, pinned in `.tool-versions` (`bench/.tool-versions` for
the bench). Tests run on snforge, not the deprecated `scarb cairo-test`: `scarb test` runs
`snforge test --max-n-steps 4294967295 --max-threads 4` in each package (root
`[workspace.scripts]`), on four threads rather than every core.

`snforge check-requirements` warns that scarb 2.21.0 is above snforge 0.64.1's "maximal
recommended 2.20.1". Ignore it: 0.64.1 predates scarb 2.21.0, everything passes on this pair, and
the next snforge release raises the maximum (foundry-rs/starknet-foundry#4624). Don't downgrade
scarb or move snforge off a release to silence it.

## Commands

From the repository root:

```bash
scarb build
scarb test                      # all packages; CI runs `scarb test -p <package>` for each
scarb test -p beast_composer -- <name filter> --include-ignored   # e.g. one parity fixture
scarb fmt --check
git diff --exit-code Scarb.lock # CI requires the lock to be unchanged after the tests
```

Gas benchmark (needs `npm install --prefix offchain/beast-sound` once):

```bash
python3 bench/scripts/gas_bench.py run --out bench/snapshots/candidate.json
python3 bench/scripts/gas_bench.py compare bench/snapshots/baseline-25be776.json \
    bench/snapshots/candidate.json --markdown
```

## Testing rules

- Contract tests deploy with `declare("<Contract>")` and `deploy`; mock contracts live in
  `#[cfg(test)]` modules.
- The `#[ignore]`d parity fixtures compare the composer with the JS engine. Run them for any change
  to `beast_composer` or `midi` (`TESTING.md`, `scripts/*_parity_cairo.sh` + `scripts/*_parity.mjs`).
  Those scripts kill every `snforge test` process on the machine past their memory limit: run
  nothing else under snforge meanwhile.
- A test run keeps what it allocates; keep each test under about 1B gas so CI's 4-core runner holds
  four at once (split large differential tests by range).
- Generated files (`core/midi_contracts/src/page/page_data.cairo`, `page/tests.cairo`,
  `beasts/beast_contracts/src/synth_settings.cairo`) change only through their generators.
- BeastMidiProvider's CASM must stay under 81,920 felts; the bench reports it.

## Commits and pull requests

Commit messages use a prefix (`perf:`, `chore:`, `docs:`, `test:`) and an imperative summary.
Branches are pushed to the `loothero` fork and opened as drafts against
`caseywescott/midi_fun_contract` `main`.
