# Beast Sound: how to change the music

A practical guide to making Beast themes more complex or more ornamented, and to changing how
they sound. Paths are relative to `midi_fun_contract/`.

---

## 1. Where the music comes from

```
token ID + live stats
   │  map_v3_beast_to_composition_params        (beast_v3_sound.cairo · engine.js mapV3)
   ▼
BeastCompositionParams  (key, mode, voices, sections, stretto, ornament density, tempo, …)
   │  engine v1: build_beast_form                (beast_score.cairo · engine.js buildForm)
   │  engine v2: build_beast_form_v2             (beast_engine_v2.cairo · engine_v2.js buildFormV2)
   ▼
note events  →  score hash, MIDI, BSN1/BSN2
   │
   ▼
playback: instruments, drums, tempo, panning    (web/beast_sound/patches.js, the simulator,
                                                 offchain/beast-sound/server/player-src.js)
```

There are two kinds of change, and they follow different rules:

| Kind | Examples | Changes a Beast's score hash? | Where |
|---|---|---|---|
| **Playback** | instruments, drums, tempo slider, panning, reverb | No | JS only (`web/beast_sound/`, `offchain/beast-sound/server/`) |
| **Canonical** | notes, voices, ornaments, form, harmony, key | **Yes** | Cairo **and** JS, kept byte-identical |

Playback changes are free: edit, rebuild, redeploy. Canonical changes are the composition itself;
they must land in Cairo and JS together and must never silently alter a Beast that already has a
published score (see §5).

---

## 2. Playback changes (no score change)

### Add or tune an instrument
`web/beast_sound/patches.js`. A patch is
`{ id, name, family, gain, play(kit, dest, t, dur, freq, vel) }`.

- Building blocks: `env()` (attack/decay/sustain/release), `osc()`, `lowpass()`, `vibrato()`,
  `fm()`, `plucked()` (Karplus-Strong), `noiseBurst()`, and `chipVoice()` for 8-bit voices
  (`wave: 'p12'|'p25'|'p50'|'tri'|'saw'|'noise'`, stepped `env`, optional `vib`, `arp`, `blip`,
  `drop`).
- Automate only with `setValueAtTime` and linear/exponential ramps. Target-approach curves
  (`setTargetAtTime`) rendered unstably in testing.
- Keep each patch to a few oscillators: ornamented scores can hold 2,000+ notes.
- New chip patch in one line:
  `chip('chip_my_lead', 'My lead', 1.0, { wave: 'p25', env: { decay: 6, sustain: 0.7, release: 3 }, vib: { rate: 6, cents: 20, delay: 0.2 } })`
- Ensembles (one patch per role) are the `ENSEMBLES` list in the same file.
- Check levels offline before shipping: render each patch with `OfflineAudioContext`
  (`node-web-audio-api` in Node) and compare peak/RMS with the existing patches.

### Change the drums
- Simulator: the `makeDrums` function inside `play()` in `web/beast_sound/index.src.html`.
- Endpoint player: `drumPass()` in `offchain/beast-sound/server/scheduler.js`.
- Sounds: `chipDrum()` in `patches.js` (`kick`, `snare`, `hat`, `openhat`).
- Times are ticks: 480 per beat, 240 per eighth, 1,920 per 4-beat bar. A loop pass is rounded up
  to whole bars, so any pattern that repeats per bar stays aligned.
- Example: four-on-the-floor kick: `if (onBeat) out.push({ time, kind: 'kick', level: 0.3 })`.

### Defaults for the endpoint player
`offchain/beast-sound/server/handler.js`: default patch (`chip_tri_lead`), drums (on unless
`?drums=0`) and engine (`?engine=`).

---

## 3. Canonical knobs (change the score)

Every knob exists twice: Cairo (`src/composition/…`) and its JS mirror
(`offchain/beast-sound/src/…`). Change both.

### Ornamentation (engine v2)

| Knob | Cairo | JS | Effect |
|---|---|---|---|
| Which style a Beast gets | `ornament_style_for_density` (beast_score.cairo): ≥5 baroque, ≥3 modal canon, else common practice | `styleForDensity` (engine_v2.js) | Lower the thresholds → more Beasts get the busier styles |
| How busy each style is | `profile_baroque_ornament`, `profile_modal_canon`, `profile_common_practice` (ornamentation_v2/profiles.cairo) | `STYLES` (engine_v2.js) | The `*_bias` fields weight each ornament family; raise `trill_bias`/`turn_bias` for more baroque surface |
| Trill speed | `trill_subdivisions` (even, 2–12), `trill_count` in the style profiles | same fields in `STYLES` | More subdivisions = faster trills |
| Which ornament kinds are allowed | `v2_enabled_ornaments` (beast_engine_v2.cairo) | `enabledOrnaments` (engine_v2.js) | The suffix policy gates trills, suspensions and chromatic kinds |
| Suffix → policy | `prefix2_ornament_policy` (beast_trait_map.cairo) | `prefix2Policy` (engine.js) | Which suffixes allow trills / suspensions / chromatic approach, and their density cap |
| Ornament density | `ornament_density` in `map_v3_beast_to_composition_params` | `mapV3` (engine.js) | Suffix cap + kill bucket + crown + Summit glory, max 7 |
| Chromatic ornaments | `default_constraints().strict_diatonic` (ornamentation_v2/types.cairo) | `validateAll` scale check (engine_v2.js) | Currently `true`, so chromatic approaches always fall back. Relax it on the Beast path to let them sound |
| Ornament chord context | the `HarmonyEvent` list built in `build_beast_form_v2` | `harmony` in `buildFormV2` | Today one minor tonic triad per section (see recipe C to add a progression) |

Ornament kinds are listed in `ornamentation_v2/types.cairo` (1–35: passing, neighbors, double
neighbors, anticipation, suspensions 4-3/7-6/9-8/6-5/2-3, retardation, appoggiaturas, escapes,
échappées, cambiata, mordents, turns, trills, acciaccaturas, chromatic approaches, enclosures,
arpeggios, pedal). Each has `ornament_can_apply` and `ornament_generate` in `ornaments.cairo`, plus
`validate_all` in `validation.cairo`. JS: `canApply`, `generate`, `validateAll` in engine_v2.js.

### Texture and form

| Knob | Cairo | JS | Effect |
|---|---|---|---|
| Canon voices and intervals | `v2_offsets()` → `[0, -5, 2]`, `V2_MAX_LAG` (beast_engine_v2.cairo) | `V2_OFFSETS`, `V2_MAX_LAG` (engine_v2.js) | Followers a sixth below and a third above. **Only change after re-running the offset search** (recipe B) |
| How many canon voices a Beast plays | `v2_canon_voice_count` | `nv` in `buildFormV2` | min(voice_count, 3); voice_count comes from tier, level, kills and rank |
| Voice budget per tier | `base_voice_count` / `max_voice` in `type_tier_family` and `map_v3_…` | `typeTierFamily`, `mapV3` | More voices for lower tiers |
| Countersubject | `use_countersubject` in `map_v3_…`; generated by `generate_countersubject` | `use_countersubject`, `generateCountersubject` | Adds an independent line above the canon |
| Melody length | `v2_phrase_length` (36 / 28 / 24) | `icLength` | Longer melodies = more material per section. Keep Tier 4–5 ≥ 24 (shorter phrases repeat across a tier) |
| Number of sections | `sections_for_kill_bucket` (beast_trait_map.cairo) | `sectionsForKill` (engine.js) | 1–5 sections as kills grow |
| Key plan of the sections | `section_tonic_shift` (beast_score.cairo) | `sectionTonicShift` (engine.js) | Section B moves by Beast type; C falls a third when scarred |
| Stretto | `stretto_lag` from `default_stretto_plan` | `strettoLag` | Entry spacing 4 → 1 beats as kills grow |
| Scar inversion pass | `use_inversion` and the inversion pass in `build_beast_form_v2` | same in `buildFormV2` | Extra section with follower 1 an octave up |
| Mode and key | `prefix1_to_beast_key`, `familiar_dark_mode_at`, `canonical_to_melodic_mode` | `prefix1Key`, `canonicalToMelodic` | Which dark mode each prefix gets |

---

## 4. Recipes

### A. Make every Beast more ornamented (smallest change)
1. Lower the style thresholds in `ornament_style_for_density`, e.g. ≥4 baroque, ≥2 modal canon.
2. Mirror in `styleForDensity`.
3. Follow the checklist in §5.

### B. Add a fourth canon voice
A fourth voice must stay invertible at every entry lag, or Beasts lose their unique melodies (the
old `[0, -4, 3]` admitted one melody at lag 1).
1. Search offsets the way the defaults doc describes: for each candidate `[0, a, b, c]`, walk
   300 seeds under `ic_constraints_all_lags(offsets, 4)` and keep candidates with zero failures and
   ~300 distinct melodies.
2. Set `v2_offsets()` / `V2_OFFSETS` and raise the voice cap in `v2_canon_voice_count` / `nv`.
3. Checklist, including the whole-collection audit (§5 step 6): failures must stay at zero.

### C. Give the ornaments a chord progression
Right now each section has one harmony event (minor tonic). Suspensions, arpeggios and pedals
react to chords, so a progression makes them far more varied.
1. In `build_beast_form_v2`, build several `HarmonyEvent`s per section, e.g. i–iv–V–i, each
   covering a quarter of `cycle_subticks`, with `root_pc` relative to the section tonic.
2. Keep `function_label: HARMONY_FN_MINOR_TONIC` for minor chords; any other label means major
   (dominant V).
3. Mirror in `buildFormV2`.
4. Checklist.

### D. Let chromatic ornaments sound ("Bender" suffix)
1. Give the Beast path its own constraint set with `strict_diatonic: false`, passed through
   `default_config` in `build_beast_form_v2`.
2. In JS, skip the scale check in `validateAll` when that flag is off.
3. Checklist; listen for clashes, since chromatic notes are not checked against other voices.

### E. Faster or denser trills for crowned Beasts
1. In `build_beast_form_v2`, after choosing the style, set `cfg.style.trill_subdivisions = 8`
   when `params.articulation_profile == ARTICULATION_ACCENT` (crowned or Shiny + Animated).
2. Mirror in `buildFormV2` (copy the `STYLES` entry before modifying it).
3. Checklist.

### F. A new instrument (no score change)
1. Add a patch to `PATCHES` in `patches.js` (see §2).
2. Render it offline and compare levels.
3. Rebuild the simulator and the player; deploy.

---

## 5. Checklist for canonical changes

Run these in order. Every step must pass.

1. **Cairo**: edit, then
   `scarb test -- --filter beast` (all Beast tests) and
   `scarb test -- --filter test_beast_engine_v2`.
2. **JS mirror**: make the same change in `offchain/beast-sound/src/engine.js` or `engine_v2.js`.
3. **Parity fixtures from Cairo**:
   ```bash
   scarb test -- --include-ignored --filter beast_v3_parity_fixture | grep PARITY > /tmp/p.txt
   node scripts/beast_v3_parity.mjs /tmp/p.txt --write
   scarb test -- --include-ignored --filter v2_parity_fixture | grep V2PARITY > /tmp/v2.txt
   node scripts/beast_v2_parity.mjs /tmp/v2.txt --write
   ```
   Both must report every case matching Cairo.
4. **Offchain tests**: `cd offchain/beast-sound && npm test`.
5. **Listen**: `scarb test -- --include-ignored --filter v2_ab_listening_set` renders 6 Beasts ×
   5 variants as MIDI (converter in the defaults doc), or use the CLI:
   `node bin/beast-sound.mjs mainnet 52918 --engine 2 -o test.mid`.
6. **Whole collection** (for anything touching melody, voices or offsets):
   `node scripts/audit.mjs --engine 2`. Expect 0 failures and 93,225 distinct scores in both
   states.
7. **Ship**: rebuild and deploy (§6).

### Versioning: never change a published Beast silently
A Beast's score is part of its identity. Put new behavior behind a new option or engine version
(`EngineV2Options` in Cairo, `DEFAULT_V2_OPTIONS` in JS, or a new `ENGINE_VERSION`) instead of
changing what an existing version produces. Old versions stay available, so earlier renders and
score hashes stay reproducible.

---

## 6. Rebuild and deploy

```bash
# simulator page
cd web/beast_sound
npx esbuild entry.mjs --bundle --minify --format=iife --outfile=/tmp/bundle.js
python3 build.py /tmp/bundle.js snapshot.min.json index.html

# endpoint (beasts.autonomousaudio.net)
cd offchain/beast-sound
node server/build.mjs            # rebundles the player (patches + scheduler)
npx vercel deploy --prod
```

The endpoint reuses `web/beast_sound/patches.js`, so new instruments and drum sounds reach the
player after `node server/build.mjs` and a deploy.

---

## Related

- `docs/beasts/engine_v2_defaults.md`: engine v2 design decisions, findings and audit results
- `docs/beasts/ornament_port_tasks.md`: the port plan
- `offchain/beast-sound/README.md`: package API
- `offchain/beast-sound/server/README.md`: endpoint and the `token_uri` change
- `offchain/beast-sound/onchain/README.md`: the onchain path (`token_uri` → TinySynth page →
  `IMidiProvider`), its orchestration version and measured costs
- `contracts/beast_sound/README.md`: `BeastMidiProvider` and where each live input comes from
  (Summit is retired: `summit_held_seconds` is always 0 there)
