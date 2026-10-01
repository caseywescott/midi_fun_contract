# Beast Sound engine v2: Phase 0 defaults

Status: proposed defaults, implemented behind `EngineV2Options` so each can be A/B-rendered.
Overrule any of them by listening; flipping an option is a one-line change.

Engine v2 = invertible-counterpoint canon (profile 25, offsets `[0, −5, +2]`) + V2 ornaments,
driven by the same `BeastCompositionParams` the V3 mapper produces. Engine v1
(`build_beast_form`) is unchanged.

| # | Question | Default | Alternative (A/B) | Why |
|---|---|---|---|---|
| D1 | Same melody in every section? | **Yes**: one leader melody for the Beast, transposed per section; ornaments vary per section | New melody per section (the old IC renderer) | The Beast must stay recognizable; history should arrange the theme, not replace it |
| D2 | How do kills reach a 3-voice invertible canon? | **Entry lag = `stretto_lag`** (4 → 1 beats as kills grow). The melody is walked once under the constraints of **every** lag 1–4 (`ic_constraints_all_lags`), so it is invertible and clash-free at any stretto | Fixed entries 0/1/2 | Keeps "kills tighten the stretto" audible without kills ever changing the melody |
| D3 | `voice_count` and offsets | **Canon voices = min(voice_count, 3)** from `[0, −5, +2]` (answer a sixth below, third voice a third above). `voice_count` 4 guarantees the countersubject | Always 3 voices | Level/rank/kills extra voices stay audible; any prefix of the voices inherits the melody's validity |
| D4 | Articulation | **Same plan as v1** (Shiny tenuto, Animated portato, both/crown accent), applied per section after ornaments | Structural notes only | Visual traits stay audible; one rule for both engines |
| D5 | Suffix ornament policy → V2 kinds | **Remove** trills (25–26) unless `allow_trill`; suspensions + retardation (8–13) unless `allow_suspension`; chromatic approach + enclosures (29–32) unless `allow_chromatic_approach`. Density picks the style (≥5 baroque, ≥3 modal canon, else common practice) | All kinds enabled (old renderer) | Makes the 18 suffixes audibly different ("Roar" trills, "Grasp" suspends, "Bender" bends) |
| D6 | Chord context for ornaments | **Minor tonic triad** (`HARMONY_FN_MINOR_TONIC`); every Beast mode has a ♭3 | Major triad (old engine behavior) | The old engine judged ornaments against a major third in minor keys |
| D7 | Phrase length | **Tier 1–2 36, Tier 3 28, Tier 4–5 24 notes** | IC lengths (Tier 4 20, Tier 5 16) | Shortest lengths that keep melodies distinct across a tier (see findings) |
| D8 | Entropy | **Leader walk**: each draw = `poseidon(canon_seed, 'LEADER_WALK_V3', p, prior)`, still choosing only legal candidates. **Ornaments**: per-section 16-bit seed from `poseidon(ornament_seed, 'V2_ORN', section)` | 8-bit LCG (old) | Unique melodies per Beast; 65,536 ornament streams per section |
| D9 | Scars | Unchanged from v1: `use_inversion` adds a final octave-inversion pass (voice 1 up an octave) and section C falls a third | | |
| D10 | Score hash | `poseidon('BEAST_SCORE_V2', params_hash, motif_hash, events_hash)`; the events hash covers every note | Params-only hash | Commits to the exact performance |

## Findings that changed the defaults (1 Oct 2026)

- **Config 4's offsets `[0, −4, +3]` leave almost no melodies once invertibility is enforced.**
  Over 1,500 seeds: one single melody at entry lag 1, 4–16 melodies at lag 4. The existing IC
  demos (3 voices, lag 1) therefore play one shared melody for every seed, transposed. The
  8-bit seed was never the real bottleneck.
- **Walking per live state would let kills change the melody** (the constraints depend on lag and
  voice count). Fixed by walking once under the union of constraints for 3 voices × lags 1–4.
- **Offset search** (every 3-voice pair in −14..+7, 300 seeds, lags 1–4 simultaneously): 30
  configurations keep 300/300 distinct melodies with zero failures. `[0, −5, +2]` is in the
  stepwise group (≈30% leaps, against ≈58% for the alternatives) and keeps a compact range.
- **Chromatic ornaments never sound.** The V2 engine validates every ornament against the mode's
  scale (`strict_diatonic`), so chromatic approaches always fall back to a neighbor or passing
  tone. D5's chromatic gate is inaudible until `strict_diatonic` is relaxed for the Beast path.
  Enclosures (31–32) are diatonic and do sound.
- **The minor-triad fix (D6) matters:** under the old major triad, arpeggios and some suspensions
  in the (all-minor) Beast modes failed validation and fell back.

- **Whole-collection audit (93,225 identities, calm and veteran states):** zero failures and
  93,225 distinct scores in both states; melody counts identical in both, confirming history never
  changes a melody. With the old IC lengths, 39.6% of Tier 5 (16 notes) and 3.0% of Tier 4
  (20 notes) shared a melody; Tiers 1–3 were unique. Length sweep over 18,645 seeds: 16 → 39.4%,
  18 → 10.8%, 20 → 2.6%, 22 → 0.57%, 24 → 0.14%. Tiers 4–5 now use 24 notes.

Open items for listening:

- Whether 36-note phrases at Tier 1 with 5 sections + inversion pass are too long (about 2 minutes at 132 bpm)
- Whether ornaments should also avoid clashing vertically with other voices (today each voice is ornamented on its own)
