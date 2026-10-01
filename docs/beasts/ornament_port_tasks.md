# Loot Survivor - Beast Sound Ornament Port Tasks

Created: 2026-10-01  
Status: Scoped, not started  
Tags: #loot-survivor #beasts-v3 #sound #ornamentation #offchain #port #testing

Related (vault): Loot Survivor - Beast Sound Implementation Tasks, Loot Survivor - Beast Sound Plan of Attack, Loot Survivor - Beasts V3 Living Sound Technical Spec, Beast Music State Report - 2026-06-22

---

## Goal

Make the ornamented sound (invertible-counterpoint canon + V2 baroque ornaments) the Beasts V3 engine, available both in Cairo and in the offchain package `@koji/beast-sound`, with byte-identical output.

Today the V3 path (`beast_v3_sound.cairo` → `build_beast_form`) and its JS port render the canon skeleton only. These parameters are computed and hashed but **not heard**:

- `ornament_density` and the suffix ornament policy
- `canon_config_id` / `profile_id` (only picks the browser instrument sound)
- `use_compound_melody`

The ornamented renderer, `build_beast_ic_canon_midi` in `beast_score.cairo`, is the one the State Report calls the best showcase. It is not on the V3 path and is not ported.

Code lives on branch `beasts-v3-sound` in `midi_fun_contract` (pushed 2026-10-01).

---

## What is in scope

Reachable from `build_beast_ic_canon_midi`, excluding code already ported:

| Area | Cairo lines | Notes |
|---|---:|---|
| `ornamentation_v2/` (not `showcase`, `tiling`) | ~3,300 | `ornaments.cairo` = 1,337 lines, 25 ornament generators |
| `melodic_canon.cairo` subset | ~700 | leader walk, `candidates_at`, cadence targeting, imitation and clash validators |
| Profiles and configs | ~250 | only profile 25 (invertible Renaissance) and config 4 |
| `build_beast_ic_canon_midi` | ~170 | |
| **Total** | **~4,400** | ≈ 5× what is ported today (~880); est. 2,500–3,000 lines of JS |

Out of scope: `harmonic_walk`, `jazz_harmony`, `known_harmonic_*` (~900 lines). They appear in the call graph, but `use_harmonic_walk` only affects profile 24 and the Beast canon uses profile 25.

---

## Problems to fix before porting

1. **8-bit entropy.** `generate_canon_with_config_length` seeds the leader walk with `extract_bits(seed, 19, 8)` and draws every step from an LCG mod 256. `beast_ic_orn_seed` also reduces the ornament seed to 8 bits, and the V2 selection RNG is the same LCG. Result: at most ~512 distinct melodies per phrase length, so many Beasts share a melody. The V3 `build_beast_form` path does not have this problem (it uses `walk_leader_hashed`).
2. **V3 parameters ignored.** The renderer always uses 3 voices entering at ticks 0/1/2 (config 4) and never applies articulation. So `stretto_lag`, `voice_count` (level/rank/kills extra voice) and Shiny/Animated articulation would go silent.
3. **Failure modes.** The renderer asserts `exact_imitation`, `all_pairs_clash_free`, `all_pairs_octave_invertible`, and `'no valid leader step'`. Any Beast whose seed trips one cannot render. This has never been checked across the collection.

---

## Phase 0 - Decide the music (1-2 days)

- [ ] Render 8-10 V3 Beasts through the current `build_beast_ic_canon_midi` (calm / scarred / crown / Summit veteran across tiers) and listen against `build_beast_form`
- [ ] Decide how kills / stretto map onto a 3-voice invertible canon (vary entry spacing? keep fixed and move kills to form only?)
- [ ] Decide whether `voice_count` 4 means a 4th voice outside the invertible pair, or is dropped
- [ ] Decide how articulation (Shiny / Animated / crown) applies on top of V2 ornament velocities and durations
- [ ] Decide which suffix ornament policies map onto which of the 25 V2 ornament kinds (today only density picks one of 3 styles)
- [ ] Write the decisions into [[Loot Survivor - Beast Trait to Canon Mapping]]

## Phase 1 - Cairo engine v2 (1-1.5 weeks)

Keep engine v1 (`build_beast_form`) untouched so existing hashes, fixtures and demos stay valid.

- [ ] `walk_leader_banded_hashed`: same candidate filtering as `walk_leader_banded`, but each draw = `poseidon(canon_seed, 'LEADER_WALK_V3', p, ...) % cands.len()`
- [ ] Full-entropy ornament seeding: per-section seed from `poseidon(ornament_seed, section)`, plus a hashed draw (or a 32-bit LCG seeded from it) in V2 selection, gated by engine version
- [ ] `build_v3_beast_form_v2(beast, live)` returning a `BeastForm`-like event list (not `Midi`) so the MIDI/BSN encoders and score hash apply
- [ ] Apply the Phase 0 mappings (stretto, voice count, articulation, suffix → ornament kinds)
- [ ] Score hash v2 commits to every render input, including ornament style and enabled kinds
- [ ] Extend `beast_v3_parity_fixture` with v2 cases; print `PARITY` lines
- [ ] Re-measure L2 gas on devnet only if the contract route is still open

## Phase 2 - JS port (1.5-2 weeks)

In `offchain/beast-sound`, behind `ENGINE_VERSION = 2` (v1 stays the default until v2 ships).

- [ ] `melodic_canon` subset: `walk_leader_profiled` / banded walk, `candidates_at`, `pick_leader_step_random`, `cadence_target`, `pick_toward`, `pair_constraints`, `allowed_steps_multivoice_p`, `keep_within_skip`, `prefer_skip_for_profile`, `band_at`, `build_voices`, `extract_bits`
- [ ] Validators: `exact_imitation`, `all_pairs_clash_free`, `all_pairs_octave_invertible` (must throw wherever Cairo panics)
- [ ] Profile 25 + `vertical_ok`, config 4, `invertible_config_from_canon`
- [ ] `ornamentation_v2`: `types`, `pitch`, `profiles`, `selection`, `canon`, `validation`, `engine` (`ornament_canon`), and all 25 generators in `ornaments`
- [ ] v2 renderer (port of the Phase 1 Cairo function)
- [ ] Integer exactness: i32 division and modulo on negatives, u8/u16 overflow → throw, u32 LCG wrap

## Phase 3 - Prove they match (2-3 days)

- [ ] Golden fixtures covering every ornament kind at least once, all 3 V2 styles (`common_practice`, `modal_canon`, `baroque`), the inversion pass, the countersubject, and every rendered mode
- [ ] Differential check: Cairo ignored test prints score hashes for ~200 pseudo-random Beasts; `scripts/beast_v3_parity.mjs` must match all of them, including identical failures
- [ ] `npm test` stays Scarb-free (fixtures in `test/golden.json`)

## Phase 4 - Whole-collection audit (1 day)

Cheap in JS: minutes for the whole collection.

- [ ] Render all 93,225 identities (75 species × 1,243 affixes) at a neutral live state: **zero failures required**
- [ ] Count distinct motif hashes and distinct v2 leader melodies; report collisions
- [ ] Spot-check a few live states per tier (kills, scars, crown, Summit hours) for failures
- [ ] Write results into a new state report note

## Phase 5 - Package and site (2-3 days)

- [ ] **BSN2** compact format. Ornaments put notes on quarter-beat subdivisions with varying durations and velocities, so BSN1's assumptions (beat grid, one duration, rule-based velocity) no longer hold. Design a per-note duration code and velocity encoding; keep BSN1 for engine v1
- [ ] `composeBeast(beast, live, { engineVersion })`; CLI `--engine 2`
- [ ] Simulator: v1 / v2 toggle, ornament legend in the piano roll
- [ ] Update the proposal tab and package README

**Total: about 4-5 weeks.**

---

## Cheaper alternative if Sound stays offchain only

If Provable Games does not want a contract, Cairo no longer has to be the source of truth:

- [ ] Write engine v2 directly in the JS package, reusing the existing designs (25 ornament kinds, 3 style profiles, validation rules), with full-entropy draws and the V3 parameters wired in from the start
- [ ] Golden fixtures become the spec
- [ ] Skip Phase 1 and most of Phase 3

**About 2-2.5 weeks.** Trade-off: no Cairo counterpart for the ornamented music until one is ported back.

---

## Acceptance criteria

1. Every V3 parameter shown on the simulator changes what you hear, or is removed from the display.
2. No two Beasts share a leader melody except by deliberate design; the Phase 4 audit reports the numbers.
3. All 93,225 identities render with no failures.
4. JS and Cairo agree byte for byte on every fixture and on the 200-Beast differential check (only if the Cairo route is kept).
5. Engine v1 output and hashes are unchanged.
