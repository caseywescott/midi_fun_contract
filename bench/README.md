# bench: gas benchmark of the production classes

Per-call L2 (Sierra) gas of the production entry points, executed from the production-compiled
classes, over a fixed case matrix (286 cases). Every case checks its complete output against a
frozen expected table, so a change that alters behavior fails the bench instead of reporting a
saving. Each snapshot also records the CASM and Sierra sizes of the four production classes.

Nothing here is production code, and the root workspace is unaffected: `bench/` is its own Scarb
workspace with its own `Scarb.lock` and `.tool-versions`.

## Commands

Needs scarb 2.21.0, snforge 0.64.1 (`bench/.tool-versions`; with asdf the runner resolves both
from there), universal-sierra-compiler (snforge's own), node 20+ with `npm install` run once in
`offchain/beast-sound`, and python3. From the repository root:

```bash
# capture a snapshot (35 s to 4 min from a clean checkout, depending on machine load)
python3 bench/scripts/gas_bench.py run --out bench/snapshots/candidate.json

# compare it with the baseline (plain text, or --markdown; --fail-on-regression exits 3)
python3 bench/scripts/gas_bench.py compare bench/snapshots/baseline-bdfc78f.json \
    bench/snapshots/candidate.json --markdown

# run some bench tests with the pinned tools, no snapshot (e.g. after a change, or to see
# which cases a change breaks)
python3 bench/scripts/gas_bench.py test a_get_midi_s021
```

`run` takes `--threads N` (default 4). Snapshots other than `baseline-*.json` are ignored by git.

## What `run` does

1. Records the scarb, snforge, universal-sierra-compiler and node versions and the resolved
   binaries it executes (asdf shims resolved; scarb's directory is put first on snforge's `PATH`
   and the Sierra compiler is pinned with `UNIVERSAL_SIERRA_COMPILER`), the git revision, dirty
   flag and status, sha256 hashes of the tracked working tree, of the production sources (`core/`,
   `beasts/`, root `Scarb.toml`, `Scarb.lock`, `.tool-versions`) and of `bench/`, and the sha256 of
   both `Scarb.lock` files.
2. Checks the expected table: `node bench/scripts/gen_expected.mjs --check` must reproduce
   `src/expected.cairo`, `src/tests.cairo`, `src/fixtures.cairo` and `expected/cases.json` exactly.
3. Runs `scarb build` at the root and records, for each of the four production classes
   (`target/dev/<package>_<Contract>.*`), the CASM bytecode length and sha256, the Sierra program
   length and sha256, the sha256 of both class files, and the headroom under 81,920 CASM felts. It
   fails if the build changes the root `Scarb.lock`.
4. Runs `snforge test --no-optimization --tracked-resource sierra-gas --max-n-steps 50000000
   --trace-components contract-name gas --color never --max-threads N` in `bench/` (log in
   `bench/target/gas_bench/snforge.log`), sampling the peak resident memory of the process tree.
5. Verifies artifact identity (below) and fails unless all four classes are identical.
6. Parses every test's result and call tree. It fails on a non-zero exit, a failed, ignored,
   missing, duplicate or unexpected test, a summary that is not "286 passed", a test without
   exactly one top-level call to its case's contract and selector, a call without gas, a parent
   whose gas is below the sum of its nested calls, an unparsed trace line, the nested-call check
   (group M) not holding exactly, or tracked files changing during the run.
7. Writes one JSON: `measurement` (the definition below), `tools`, `git`, `expected_table`,
   `classes`, `artifact_identity`, `run` (command, threads, wall time, peak RSS), `checks`,
   `groups`, `derived` (attribution, below) and `cases`: per case its name, group, contract,
   selector, `gas`, the gas of each nested call (`nested`), the whole test's L2 gas (`test_l2_gas`,
   setup included, for reference only), the checks it passed with their sources, and labels.

## Tooling: snforge in its own workspace

- **snforge 0.64.1, own workspace.** `bench/Scarb.toml` has `[workspace]`, its own `Scarb.lock`
  and `.tool-versions` (scarb 2.21.0, starknet-foundry 0.64.1) and depends on the four packages by
  path. Scarb resolves `version.workspace`, `edition.workspace` and `midi.workspace = true` for
  path dependencies that belong to the root workspace (from the root manifest), and the bench's
  lock resolves every shared dependency to the root lock's versions and commits. With `bench/`
  present, the root `scarb build` produces the same four classes byte for byte, `scarb test -p
  <package>` passes for all four with `Scarb.lock` unchanged, and `scarb fmt --check` reports
  exactly what it reports without `bench/` (the root workspace does not see `bench/`).
- **Shadow packages for the two contract packages.** `beast_contracts` and `midi_contracts`
  declare only a `starknet-contract` target, and Scarb ignores a dependency without a lib target
  ("missing a lib or cairo-plugin target"), so `build-external-contracts` cannot reach them
  directly. `bench/deps/<package>/` holds a manifest with the production package's name, version,
  edition and dependencies plus `[lib]`, and a `src` symlink to the production sources. The crate
  is the same crate (same name, same files), and the identity check below is the guard against the
  manifests drifting. If a production manifest gains a dependency, mirror it there.
- **Mode.** In both snforge modes the four Sierra classes are byte-identical to the root build's
  `contract_class.json`, and the CASM universal-sierra-compiler makes from them is identical to the
  root build's bytecode. `--no-optimization` is used because it builds the contracts the way
  production does (the package's `starknet-contract` target, through `build-external-contracts`)
  and its scarb-compiled CASM is identical too; the default mode compiles them inside the test
  target.

## Artifact identity (re-verified every run)

For each production class, in every `starknet_artifacts.json` under `bench/target/dev` that lists
it (the starknet-contract target snforge loads with `--no-optimization`, and the test targets):
the Sierra class file's sha256 equals the root build's; the scarb-compiled CASM bytecode's sha256
equals the root build's; and the pinned universal-sierra-compiler (the binary snforge compiles
with) compiles that Sierra to bytecode and hints equal to the root build's. The snapshot's
`artifact_identity` records every hash. Whichever of the two snforge executes (the scarb CASM, or
CASM it compiles from that Sierra with that binary), it is the production bytecode.

## What a gas number means

`gas` is the L2 gas (Sierra gas, `tracked_resource = sierra-gas`) of the case's one top-level call
from the test function: the `[L2 gas]` of that call in snforge's call trace. It is **inclusive of
the calls it makes**: `get_midi` includes the NFT's `get_beast_rank`, `token_uri` end to end
includes the provider's `get_midi_for`. Group M shows this exactly on every run: with an NFT whose
`get_beast_rank` costs 1,941,450 more, `get_midi` costs 1,941,450 more. The nested calls' own
numbers are in `nested`, so exclusive costs are a subtraction (for instance `token_uri` end to end
minus its nested `get_midi_for` equals `token_uri` on the same bytes from the fixed-bytes provider
minus that provider's call, to the unit: 97,936,550 for species 1, 110,226,820 for 32 shiny).

It excludes the test body (deploys, mock setters, output digests) and any transaction overhead
(account validation, calldata and L1 data costs): it is the execution gas of the call itself, which
is what changes when the code changes. `--gas-report` aggregates per selector and
`--save-trace-data` writes about 36 MB per test (the VM trace), so the bench reads the trace
components instead. The numbers are deterministic: identical across thread counts and across
clean captures.

Limits: Starknet 0.14.x allows a transaction's execution `execute_max_sierra_gas` =
1,110,000,000 L2 gas; snforge does not enforce it (a single call of 1,133,970,050 passes), so the
runner flags any case above it (none at the baseline: the heaviest is `c_token_uri_e2e_s032_s` at
466,035,973, the heaviest `get_midi` 361,826,223). snforge caps VM steps per test instead, at
10,000,000 by default (a test of 9,947,415 steps passes, one about 85,000 steps longer fails
with "RunResources has no remaining steps"); the heaviest bench test takes
4.2 M steps, and the runner passes `--max-n-steps 50000000` so that a heavier candidate is
measured rather than cut off. `starknet_call` limits are set by each node.

## The case matrix (286 cases)

| Group | Cases | Contract | What |
|---|---:|---|---|
| A | 180 | BeastMidiProvider (production) | `get_midi` for species 1-75 x shiny (the Beasts of `genesis_parity_range`: prefix 0, level 1, health 100, animated 0, the species' tier and type), community species 76 (Agony Bane Gloomfang), 77 (tier 1 Brute, shiny) and 200 (tier 5 Magic), and the Sorrow Peak Warlock (named, level 126); `get_midi_for` (21, 1, 32 shiny); `get_sound` (1, 1 shiny, Yeti 68, swapped 39, community 76, lightest 21); `get_settings` (each type x shiny, Yeti x shiny, 39, 40); `get_live_state` (genesis Warlock with Death Mountain, Sorrow Peak Warlock with scars, the same without Death Mountain, community 76); `get_collection`, `get_engine_version`, `owner` |
| B | 28 | BeastSoundComposer (production) | its 7 views x 4 Beasts (tier 5 fresh, Sorrow Peak Warlock, tier 1 with 3 sections, `heaviest()` with `live(200, 63, 1, 1243)`), deployed with `('LS_V3_DEMO_SALT', 500)` |
| C | 9 | MidiSoundPage (production) | `token_uri` with a fixed-bytes provider (MIDI of 31, 1,406, 4,726 and 7,197 bytes: synthetic, and the real Genesis Tracks of 21, 1 and 32 shiny) and the real Sepolia Warlock's members (2,275 B) and SVG base64 (30,128 B); the same with a member containing `#` and `%` (`append_escaped`); with the page tests' small members and SVG; end to end with BeastMidiProvider for 1 and 32 shiny; `get_midi_provider` |
| D | 6 | ScaleMidiProvider (production) | `get_midi` and `get_midi_for` for tokens 1, 42 and a Beasts token ID |
| E | 62 | BenchLib, BenchGenesis, BenchScore (bench probes) | library attribution, below |
| M | 1 | BeastMidiProvider | the nested-call check |

Labels in `expected/cases.json` and the snapshot name the special species: the Yeti (68), the
Harpy/Pegasus swap (39 and 40 play each other's track), Nue (33, Phrygian), the lightest file (21)
and the largest (32 shiny). Every test makes exactly one call to its measured entry point; the
mocks (`src/mocks.cairo`) are copies of the ones in `beasts/beast_contracts/src/tests.cairo` with
the same semantics (`get_beast_rank` reverts for an unminted token).

### Group E: library attribution

The probes are entry points of bench contracts (`src/probes.cairo`), so their gas is read per call
like any other case; each builds its input inside the call and returns the function's output. The
`*_input` rows build the same input and return only its length, and `u8_output`/`felt_output`
return arrays of a given size, so `derived` in the snapshot holds differences of measured calls:

- `bytes_to_byte_array` and `to_felt252_array` at 0, 1, 30, 31, 32, 62, 1,406 and 7,197 bytes,
  minus `pack_input` (building the synthetic bytes, which is the larger part).
- `append_base64` and `midi_html` on the four MIDI fixtures, minus `b64_input`.
- Stages on species 21, 1 and 32 shiny. T0 = `genesis_smf_bytes(beast)` (BenchGenesis), minus the
  cost of returning that many bytes as an `Array<u8>` (`u8_output - pack_input`); T1 = the Genesis
  Track's parameters and `build_v11_score_with` (BenchScore; the parameter setup is a copy of the
  genesis branch of the private `genesis::compose`, about 50 lines that call public functions),
  minus building and returning its result (`felt_output`). `after_score` = T0 net - T1 net (voice
  statistics, the Genesis channel pick, the inner-voice ties, the Yeti special, the arrangement
  and SMF writing); `provider_dispatch_and_packing` = `get_midi` - T0 net. The stages after the
  score (`voice_stats`, `genesis_pick`, `tie_repeats`) are private and are not probed separately:
  reaching them would need a production change or a copy of them.
- `genesis_smf_bytes` directly for 13 species (lightest, heaviest, Yeti, the swaps, Nue,
  community, both shiny states): the library without the provider's dispatch.

## Correctness binding

Every case checks its whole output in the test body (outside the measured call) with
`src/digest.cairo`, which does not use the code under test:

- MIDI and other bytes (`get_midi`, `get_midi_for`, `get_sound().midi`, `token_uri`, the scale
  MIDI, base64, `bytes_to_byte_array`, `genesis_smf_bytes`): `(byte_len, poseidon([byte_len,
  31-byte words...]))`, the digest `scripts/genesis_parity.mjs` compares (`bytesToFelts`, then
  `poseidonHashMany`), taken from the ByteArray's own serialization.
- Everything else (settings, live-state reports, composer views, addresses, probe results):
  `(felt_count, poseidon(felts))` of the Serde serialization.

A mismatch fails the test with `DIGEST MISMATCH <KEY>: got (...), expected (...)`.

The expected values (`src/expected.cairo`, with each one's source in `expected/cases.json`) come
from two places:

- **js** (233 checks): the independent JS engine in `offchain/beast-sound`: `genesisMidi(id,
  shiny, E, v11)` from `src/lab.js` for species 1-75 (and the lab's `sampleTrackMidi` with the
  Genesis defaults on the token's tier and type for the community species), the page's `tokenUri`
  (`onchain/page.js` with `onchain/dist/stored.b64`, whose length is the Cairo `STORED_LEN`),
  Buffer base64 and `midiHtml`, and plain packing for the probes.
- **baseline-frozen** (59 checks): the Cairo output at the baseline (2ce04a9), recorded once by
  `gas_bench.py freeze` into `expected/frozen.json`: settings, live-state reports, composer views,
  the scale MIDI, the T1 score, the collection and provider addresses.

`frozen.json` also records the baseline's value of every js check, and the generator fails if any
differs: at 2ce04a9 all 233 agree, community species included.

**The table is never regenerated from a candidate.** `scripts/gen_expected.mjs` computes the js
values from the JS engine alone and copies the frozen ones from `frozen.json`, so rerunning it
reproduces the same files. `gas_bench.py freeze` refuses to run if `frozen.json` exists, or if the
production sources differ from `--baseline-rev`. A candidate that changes an output fails the
bench; a deliberate change of the music is a new baseline, made by freezing at that commit.

Checked by mutation in a scratch copy (not committed): lowering the velocity of the first note of
voice 0 in `full_midi.cairo` failed 179 cases, each on its own `DIGEST MISMATCH` (every case that
returns a Genesis Track: 154 `get_midi`, 3 `get_midi_for`, 6 `get_sound`, 2 end-to-end
`token_uri`, 13 direct `genesis_smf_bytes`, group M); adding 1 to the last byte of the first word
in `midi::pack::bytes_to_byte_array` failed 177, each on its own `DIGEST MISMATCH` (the provider
cases, the end-to-end pages, the 6 scale cases, and `bytes_to_byte_array` at 31 bytes and more,
not at 0, 1 or 30). To repeat: copy the repository without `.git`, make the change, and run
`python3 bench/scripts/gas_bench.py test` in the copy.

## Compare

`compare` refuses (exit 2) if the schemas, measurement definitions, scarb, snforge or Sierra
compiler versions, case sets (name, group, contract, selector, checks) or expected tables differ.
It prints, per group, the count, base and candidate sums and the min, median and max per-case
delta; per class, the CASM and Sierra sizes and deltas and the headroom under 81,920 felts; and
every case's base, candidate, absolute and percentage delta. A case that costs more, a class over
the CASM limit or a case over `execute_max_sierra_gas` is listed under REGRESSIONS. It warns when
`bench/` itself differs between the two snapshots (the mocks and probes are inside the inclusive
numbers) or a snapshot was taken from a dirty tree.

## Runtime and memory

On this machine (32 cores, shared with other builds), a full `run` from a clean checkout (both
`target` directories deleted) took between 35 s and 3.6 min, most of it compiling, depending on
the other load; with the build cached the snforge run takes 10 to 20 s. Peak resident memory of the whole run's process tree is
about 12.6 GB at 8 threads (the snforge run: about 11 GB at 4 threads, 13 GB at 8, 15 GB at 12, with
identical gas). The default is 4 threads, at most half of a current laptop's cores.

## Changing the matrix

Edit the matrix in `scripts/gen_expected.mjs` (and `src/cases.cairo` for a new kind of case), then
run `node bench/scripts/gen_expected.mjs`. A new js check works at once; a new baseline-frozen
check needs a freeze at the baseline commit (delete `frozen.json` there and run
`python3 bench/scripts/gas_bench.py freeze --baseline-rev <rev>`), and a new matrix needs a new
baseline snapshot, since `compare` refuses different case sets.

## Files

| Path | What |
|---|---|
| `Scarb.toml`, `Scarb.lock`, `.tool-versions` | the bench workspace |
| `deps/beast_contracts`, `deps/midi_contracts` | the shadow lib packages (manifest + `src` symlink) |
| `src/mocks.cairo` | MockBeasts, MockDeathMountain (copies), BurnBeasts (group M) |
| `src/probes.cairo` | FixedMidiProvider, BenchLib, BenchGenesis, BenchScore |
| `src/cases.cairo` | what each kind of case deploys, calls and checks |
| `src/digest.cairo` | the output digests and `check` |
| `src/tests.cairo`, `src/expected.cairo`, `src/fixtures.cairo` | generated: one test per case, the expected table, the page fixtures |
| `expected/cases.json` | generated: every case and check with its source |
| `expected/frozen.json` | the baseline's outputs (`gas_bench.py freeze`) |
| `scripts/gen_expected.mjs` | the matrix and the expected-table generator |
| `scripts/gas_bench.py` | run, compare, test, freeze |
| `snapshots/baseline-bdfc78f.json` | the current baseline: the classes after the gas work |
| `snapshots/baseline-2ce04a9.json` | the classes before it (`2ce04a9`, where the bench was frozen) |
