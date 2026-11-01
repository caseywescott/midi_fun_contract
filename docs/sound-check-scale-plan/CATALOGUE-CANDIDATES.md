# Implemented Sound Check audition candidates

The general catalogue now has a single JS data source at `offchain/beast-sound/src/sound_check_catalogue_data.js`, with a generated compact Cairo table. These are **listening candidates**, not claims of artistic approval. Cyclops64 delegates to the separate exact504 implementation.

The74 general warmups use8-bar loops: an individual head, two held tones, an answering phrase and40-tick articulation notes with an intentional ending rest. They retain the planned essential-family presets and mega lead parity, varied rhythm grids/tempos and optional gentle pan response. Eleven otherwise duplicate draft heads received individual in-mode tone changes; the rendered pitch/time gestures are now distinct across all74 general species. The canonical data records these edits explicitly.

Unnamed39/40 use their swapped Species Song keys. Satori44 and AgonyBane name1 warm up the approved411 target in A Aeolian at120BPM; other named checks keep their existing name-derived key. Names retain the species' curated preset and phrase instead of shuffling the preset. The Satori check uses its existing Hunter-family voice, avoiding an unrelated settings expansion. Written check inputs still declare their own mode/tonic; the writer folds their tonic pitch class into the row's comfortable octave. Accepted modes, tonic0–103, names0–1242 and future u32 species remain supported.

The recipe family remains independently selectable. When it differs from the source species family, the normal voice comes from the selected family's first catalogue row, so MIDI programs always exist in the matching settings bank. Mega retains the source row's 50/65 choice. Canonical species/family pairings keep their reviewed program.

Performance uses the existing tempo/velocity/articulation rules for the general checks. A short gate is never lengthened by the60-tick articulation floor. Both MIDI tracks retain End-of-Track15360, so ending rests survive looping. Each loop reestablishes its initial pan; optional call/response pan resets to center before the cadence.

Verification commands from the repository root:

```sh
node scripts/check_catalogue.mjs --check
node scripts/check_catalogue_parity.mjs --check
node --test offchain/beast-sound/test/check-catalogue.test.mjs
(cd beasts/beast_composer && snforge test --max-n-steps 4294967295 --max-threads 2 catalogue_parity_)
(cd beasts/beast_composer && snforge test --max-n-steps 4294967295 --max-threads 2 catalogue_boundaries)
```

The generated fixture compares384 independent JS/Cairo cases:75species×4effects plus names1/621/1242 for seven representative species×4effects. Twelve extra cases cover future-species/tonic/mode/expression boundaries. Existing production adapters should read each candidate's encoded source tempo and full End-of-Track rather than assuming120BPM or truncating at the last note-off. The final combined source has passed all 300 shared Check MIDI/settings comparisons through a declared production class and the Sound Lab's full 1,635-case Cairo matrix. The combined Composer fits at 81,920 / 81,920 CASM felts; see the parent validation record for the pinned toolchain and artifact hash.
