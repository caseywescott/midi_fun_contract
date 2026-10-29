# Shared musical datatypes and call compatibility

`beast_composer_inputs` is the canonical data/codec package shared with the
Beasts Sound Manager. This package contains no music generator, MIDI renderer,
NFT decoder, sales/selection policy, network calls or deployed contract.

The package uses compiler-provided Starknet `Store` derives and imports no
MIDI/player implementation. Beasts uses Scarb 2.20; MIDI uses Scarb 2.21. The
composer library re-exports the exact types as `beast_composer::inputs`.

## Wire contracts

The authoritative fields and validation are in `src/lib.cairo`. Composition
codec 4 is `[4, CairoSerde(ComposerInputs)]`, with B1 SoundCheck data tag 0
and Song tag 1. Generation codec 2 is `[2, CairoSerde(base_song)]` without a
composition discriminator. Every declared scalar/enum/boolean field is preserved;
unknown versions, invalid ranges, boolean aliases, truncation and trailing data
reject. Zero seeds are ordinary values. The independent JS wire codec and types
are exported as `beast-sound/inputs`; it contains no performance transformation.

SoundCheck's tag/data shape remains for byte compatibility with the existing
Beasts manager and the legacy SoundCheck concept already in the library.
This PR adds no SoundCheck audio implementation. Likewise, fields describing
section rhythm, expression and arrangement are data contracts; interpreting them
is separate runtime work. `EditionCompositionConfig` and `GenerationInputs` carry
an immutable config/base, not a clock, sale mechanism or generation algorithm.

`normalize_generation_identity` validates and preserves the supplied species/name
identity. Storage packing in a manager is independent of this wire representation;
`Store` derives do not prescribe storing full recipes for every purchase.

## Call interfaces and current integration

`beast_contracts::pure_generator::IBeastPureGenerator` declares
`get_generation_inputs(config, edition_id, identity)` and
`generate_inputs(base, variation_identity)`. The matching
`pure_composer::IBeastPureComposer` declares
`compose(inputs, sound_effects) -> TinySynthSound`. These declarations establish
argument/result wire agreement and include no deployed implementation.

Current consumers are Beasts `packages/sound_manager/src/engine.cairo`,
`records.cairo`, `stored_purchase.cairo` and `originals.cairo`. The existing Beasts
integration stays pinned to full B1
`eebed3a773283d4e103c1042ac372ba4bbf50f61`, which supplies its tested runtime.
This core is not a drop-in replacement backend or a complete replacement for that
manager's dependency (optional Evolution context is separate). It does not change
the legacy provider's 116-bit token decoder to the new 251-bit schema. No provider
bridge, extra contract call, downstream source/pin or fixture change is added.

Compatibility qualification uses fixed independent Cairo/JS vectors, compiler
Store tests and an isolated actual-manager-ABI probe against frozen B1 classes.
That probe demonstrates B1-backed interface compatibility; it does not claim this
core generates music. Optional reference runtime, explicit-input SoundCheck and
Evolution remain separate reviewable extensions. Existing upstream composition
and provider runtime logic remains unchanged.
