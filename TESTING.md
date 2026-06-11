# Testing without crashing your laptop

Heavy MIDI-export tests print large `Message::` streams to stdout. Running all **521** tests at once can spike CPU/RAM and freeze the machine.

## Safe default: unit tests only

```bash
./scripts/run_unit_tests.sh
```

Runs ~25 light modules one at a time with a **3s pause** between each (override with `SCARB_TEST_SLEEP=5`).

Skipped by design: `midi_2_cairo_print`, `test_*_midi` (MIDI dump tests).

## Full `scarb test` is now lighter

MIDI-export tests are marked `#[ignore]`. Plain `scarb test` skips them (~160 fewer heavy runs).

To include ignored tests:

```bash
scarb test -- --include-ignored
```

## Generate one MIDI (recommended)

```bash
./scripts/generate_midi_from_test.sh \
  renaissance_canon_long_3voice_v2_ornamented_midi_test \
  demos/renaissance/renaissance_canon_long_3voice_v2_ornamented.mid
```

## Generate v2 ornament showcase (batched)

```bash
# Catalog only (~1 heavy test)
CATALOG_ONLY=1 ./scripts/generate_ornamentation_v2_demo_midis.sh

# 10 kinds at a time, 5s cooldown between each
SCARB_TEST_SLEEP=5 BATCH=1 BATCH_SIZE=10 ./scripts/generate_ornamentation_v2_demo_midis.sh
SCARB_TEST_SLEEP=5 BATCH=2 BATCH_SIZE=10 ./scripts/generate_ornamentation_v2_demo_midis.sh
SCARB_TEST_SLEEP=5 BATCH=3 BATCH_SIZE=10 ./scripts/generate_ornamentation_v2_demo_midis.sh
SCARB_TEST_SLEEP=5 BATCH=4 BATCH_SIZE=10 ./scripts/generate_ornamentation_v2_demo_midis.sh
```

## Manual single test

```bash
scarb test -- --include-ignored --filter ornament_v2_01_passing_asc_midi_test
```

## Tips

| Problem | Fix |
|--------|-----|
| Thermal throttling / fan max | Increase `SCARB_TEST_SLEEP` (e.g. 8–10) |
| Out of memory | Run batched scripts; never pipe full suite to a file |
| Slow compile | Scripts call `scarb build` once before a batch |
| CI needs MIDI tests | `scarb test -- --include-ignored --filter test_ornamentation_v2_midi` |
