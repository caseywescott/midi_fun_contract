# Cyclops original 504 implementation

Species64 retains the entire authored eight-sound sequence: programs34–41,72 notes and38400 ticks. NormalFX0 is the exact original504 MIDI (735bytes, SHA-256 `03783872ada54c91052ceb70fb80f35b4553702256ee589695c9eb09e6ce2ecb`) and exact original772-byte settings text.

## Four standard Check performances

The user's correction supersedes the earlier all-effects-identical policy. Cyclops now follows the same Check tempo, gate and velocity rules as the other74 species. Its Mega performances keep the eight Arp/FX programs instead of replacing the selected bank with50/65. No echo, octave doubling or new composition structure is added.

| FX | Performance | Tempo (microseconds/quarter) | Loop seconds | Notes |
|---|---|---:|---:|---|
|0|Normal|342857|27.42856|Exact original504;440/1100/58-tick gates, velocity100|
|1|Mega|317857|25.42856|Standard25000us acceleration, tenuto; eight original timbres retained|
|2|Portato|312857|25.02856|Standard30000us acceleration;330/825/58-tick gates, original short blips preserved|
|3|Mega/accent|297857|23.82856|Standard45000us acceleration, bar-downbeat accents100/108|

Names do not retune this authored piece; all72 pitches and all eight program changes remain in their original order. The settings bank remains the same across0–3. Four distinct MIDI performances are expected even though the instrument slots/settings are retained. The helper supports the existing accepted custom Check articulation/velocity inputs too.

The settings generator supplies only the eight timbres and their three sampled pulse waves. No input codec, storage, network service, family-wide bank expansion or generic effects rule changes are introduced. The legacy lab installs these programs. The sampler must apply its existing `performCheck` to this authored Check, retaining `settingsKey: cyclops-check`; remove the prior authored-output bypass.

## Stored recipe compatibility

`sound_check_inputs` now explicitly writes Cyclops's actual342857us normal tempo before `apply_performance`. Previously the authored renderer ignored the recipe tempo; older Cyclops recipes may contain the provisional catalogue tempo instead. New input/fixture generation must use the new authoring function. An old recipe's stored tempo is now honored and is not silently reinterpreted as175BPM. Existing shared entries cannot be overwritten: append/reselect a newly authored Check when integrating the engine release. No V3 fixture repin, storage mutation or publication is performed by this source change.

## Verification

Independent normal504 MIDI/settings fixtures remain unchanged. The four-effect fixture comes from the existing production adapter's standard Check transform, and focused Cairo captures compare actual output against those bytes. Generated catalogue parity updates the three changed Cyclops effect expectations; other species expectations remain unchanged. The final combined source was independently qualified at 81,920 / 81,920 CASM felts; all 300 shared Checks match MIDI/settings through the declared class. The Sound Lab also passed its full 1,635-case actual Cairo matrix. See the parent validation record for the pinned toolchain and artifact hash.
