# Optional Song and generator reference

This is an optional runtime add-on to the shared compatibility core, not part of
that core's functionality. Casey and his team own the final musical algorithm.
The core data/interface commit supplies no music or replacement provider.

This reference restores the reviewed B1 normalized Song writer, complete matching
TinySynth settings, transient Song performance0–3, deterministic edition-template
factory and fixed-sample generator. It includes the existing reference choices
for normalized pitch bounds, authored arrangements, sample-shape variation and
explicit per-section rhythm. These are reference policies, not token-schema fixes;
none is retuned by this extraction. Existing upstream entrypoints are retained.

`BeastPureGenerator` supplies `get_generation_inputs` and `generate_inputs`.
`BeastPureComposer.compose` supports Song here. The core's SoundCheck wire variant
remains data-compatible, but this partial reference explicitly rejects it with
`Sound Check extension required`; it does not invent audio or discard fields.
The separate SoundCheck add-on supplies that path. Evolution is separate too.
Consequently this branch alone is not a complete replacement for the current
Beasts manager's full B1 backend. Beasts remains pinned to immutable B1eebed3a;
no downstream source, pin, fixture or deployed state is changed.

The source review stack is core → Song/generator reference → explicit SoundCheck
→ Evolution. This organization separates wrapper changes and provides precise
incremental comparisons; it does not assert that Evolution musically requires
SoundCheck. Each optional upstream draft includes prerequisite commits in its
full main diff until they merge and the branch is rebased.
