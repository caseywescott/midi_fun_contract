# Optional explicit-input SoundCheck reference

Casey main already contains `composition::sound_check::sound_check_smf_bytes`,
which auditions a Beast's scale through its preset family and drum kit. That
legacy implementation and its existing callers remain unchanged by this add-on.
The shared compatibility core retains SoundCheck's B1 tag0/data shape only.

This optional add-on implements the new explicit-input path for the reference
composer. `sound_check_from_inputs` consumes supplied identity, mode, tonic,
family, tempo, velocity ceiling and articulation directly; `compose` returns
matching MIDI and TinySynth settings. The reference's transient performance0–3
mapping now applies to this path too. No new musical tuning is introduced during
extraction: the implementation is the previously tested B1 reference.

Its dependency is the optional Song/generator reference wrapper, not merely the
shared data package. This is a source-review stack; existing upstream SoundCheck
does not need the new reference or its policies. This branch supports Song and
explicit SoundCheck; Evolution is a later optional add-on. The full Beasts B1
backend/pin remains unchanged, and Casey and his team own the final algorithm.
