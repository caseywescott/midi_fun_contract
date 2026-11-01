# Agony Bane Satori: a named composition derived from lab411

The shared Satori Species Song remains the exact original lab411 MIDI and untrimmed settings. The user additionally requested a recognizably different Agony Bane composition derived from that base. This is scoped to species 44/name 1; it does not reseed all names, change Manager architecture, or promise unique themes for every name.

## Written FX0 result for listening review

| Written property | Shared Satori | Agony Bane Satori |
|---|---|---|
| Mode and mapped home | A Aeolian, tonic 57 | C Aeolian, tonic 48 |
| Authored register treatment | 2 | 0 (Casey's low named register) |
| Ornament profile | 0 | 1, no trill (Casey's Bane profile) |
| Progression | Am–F–C–G | Cm–Ab–Eb–Bb |
| Lead rhythm per active bar | 4:2:1:1 eighth-note slots | 3:3:1:1 eighth-note slots |
| First held lead gate / next onset | 920 ticks / 960 ticks | 680 ticks / 720 ticks |
| Duration and arrangement | 36 bars / 72 seconds at 120 BPM | Same entrances, break, progression relationship and form |
| Palette | Triangle Lead 0, Triangle Pluck 15, Chip Harp 17 and original drums | Same palette and original mix |

The named rendition moves all 960 pitched notes nine semitones down and brings 28 answering lead notes one eighth note earlier. Its melodic interval/order sequence, bass and harp patterns, drums and 48–56 second break remain related to #411. Tests compare actual parsed note events, not just recipe metadata or hashes. This is a distinct low-register rhythmic interpretation of the existing motif, rather than a new unrelated theme.

The implementation copies Casey's named mode, tonic, ornament density and trill controls from the existing procedural named base. Casey's procedural `ThemeInputs.register_band` retains the species motif's register; the named register is encoded in its mapped tonic 48/60/72 plus pitch class. The authored record selects its register treatment from that named tonic. JS checks the same controls through the unchanged `engine.mapV3` mapping. Relevant source is `genesis.cairo::song_inputs`, especially its species-theme choice and named-key override, and `lab.js::sampleTrackMidi`'s `theme === 'species'` branch. Neither generic mechanism is replaced.

Only new Satori name 0/name 1 generation defaults select the existing dual authored markers. The schema 5/generation 2 wire format and storage layout remain unchanged. Old unmarked recipes and other Satori names retain Casey's implementation. Earlier marked name 1 bases with the shared register 2 still retain their original written note/timing interpretation; low register 0 explicitly selects the new phrase treatment. Drift retains this register treatment even when its existing weekly rule changes ornament density. Shared register 2 does not silently acquire the named phrase through drift.

New edition-zero purchases from the named base retain its C-minor key and low-register phrase, with deterministic seed-tempo variation. Existing shared-base purchase treatment is retained. Historical purchases use their snapshotted base; edition 1+ remains Casey's existing style engine, without a new authored-score edition framework.

## Full Casey sound-effect behavior

The earlier palette exemption is removed. The authored score now uses the same `beast_v11::shape` phrase dynamics and `full_midi::beast_form_to_full_tracks_arranged` mega/echo arrangement as ordinary Casey Songs. The JS counterpart uses the existing v1.1 shaper and `beastFullMidi`. The contract/codec/storage architecture is unchanged.

| Effect | Actual arrangement |
|---|---|
| 0 | Exact original authored MIDI encoding, pan/channel mix and settings; name 1 retains its derived written composition |
| 1 | Casey mega lead 50/65, opposite-panned octave double on the other mega lead at 75% velocity, full mega drum groove, normal tenuto gates and phrase dynamics |
| 2 | Casey echo on Hunter first pluck 12, 360 ticks later at 50% velocity, opposite pan and loop-end clipping; portato gates and phrase dynamics; the authored drum score is retained in Casey's compact running-status encoding |
| 3 | Both mega and echo, including octave double, full mega groove, full written profile 3 gates and Casey phrase dynamics |

Mega lead choice is `(species + name) % 2`: shared Satori selects 50 with 65 as its double, while Agony Bane selects 65 with 50 as its double. The highest-mean-pitch voice is selected by the existing arranger. Base voices are 0–2, the octave double is 3, and echo is 3 when alone or 4 with the double. Effects use the normal Casey three-voice pans 9/64/118 and the lead's opposite pan 119; normal FX0 retains the reviewed 50/40/80 pans and CC7=100 mix. The normal authored note dynamics remain exact at FX0; effects 1–3 use Casey's pitch-range phrase arc and alternating bar-downbeat emphasis, rather than the earlier fixed-velocity approximation. Existing performance tempo adjustments produce 500000/475000/470000/455000 microseconds per quarter note for effects 0/1/2/3.

Mega uses the existing full Casey groove, including sixteenth hats and tier fills from the beginning. The authored pitched entrances and lead break remain; the standard mega groove replaces the authored drum intro/break. Echo-only retains the original drum arrangement. These behaviors are explicit uses of the existing arranger, not new effect profiles.

Settings are generated separately for all four combinations. FX0 remains the original exact palette/mix. Mega installs 50/65 and the standard existing drum kit, including toms for all accepted tier fills; echo installs 12. The original triangle/pluck/harp timbres and untrimmed balance remain available. No new waveform definition, external service or Composer class is introduced.

The named track continues receiving token `sound_effects`. Selection of a fixed global shared-Species-Song effect preset is a separate Manager policy and is not implemented here. The corrected combined production Composer, including all four Cyclops performances, builds to exactly 81,920 CASM felts against the 81,920 limit with Scarb 2.21.0. Its compiled class SHA256 is `55e03473d99bd4642ffb2554dca47f11c346054f17129d3c769b0fe7d011e42c`; CI now checks the real production artifacts.

## Verification

- Final source passes 143 JS tests, 369 non-ignored composer tests and 77 contracts tests. All 154 ignored Composer fixtures and 13 JS/Cairo comparisons also pass, including the complete 150-case drift matrix. Cairo checks use Foundry 0.64.1.
- Exact shared411 MIDI (9,720 bytes) and original synth settings remain unchanged.
- Node tests compare Casey's actual mapped fields, normalized progression/contour, real note timing, current codecs, old markers, purchased-base key inheritance and gate rules.
- Cairo tests compare all eight shared/named effect MIDI fingerprints, the named canonical wire hash, all four composed settings-bank hashes, drift marker/register preservation and the 60 tick staccato gate. Existing Casey shape/oracle regressions verify the shared dynamics helper remains unchanged.
- Legacy written, named and seeded entry points now dispatch to the authored base consistently, including legacy provider settings. Drift is applied once, and both purchase helpers retain the markers. Regression tests cover route equality, purchased/seeded drift and the preview form/drift metadata. All 75 edition species genomes remain equal to the shipped Cairo table.
- The actual separately compiled production class passed 1,635 matrix cases plus 36 mixed-family cases. All 600 canonical lab samples and 16 explicit authored references remain unchanged. The [parent validation record](../README.md#validation-and-size) identifies capture revisions and final artifact equivalence. The downstream V3 engine pin and stored track selection remain separate integration work.

The independent effect oracle uses the original lab411 generator and an unmodified copy of Casey's `full_midi.js` pinned to `cdcad0a`; its phrase shaping is checked independently against the readable v1.1 policy. Production-renderer output is not used to generate its own expected result. `full-effects-golden.json` records the independently derived bytes, SHA256, tempo, tracks, programs and note counts. Feature tests additionally assert actual octave/pitch/velocity ratios, echo delay/tail clipping, opposite pan, selected settings coverage and sixteenth mega hats.
