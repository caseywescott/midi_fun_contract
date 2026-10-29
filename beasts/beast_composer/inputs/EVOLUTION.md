# Optional Evolution reference

This add-on is stacked on the shared compatibility core (upstream draft #18),
the optional [Song/generator reference](../REFERENCE.md), and the optional
[explicit SoundCheck reference](SOUND_CHECK.md). The source-wrapper stack is a
review organization, not a claim that Evolution musically requires SoundCheck.
Core #18 supplies no runtime class. This is a reference for integration; Casey
and his team own the final algorithm. Ordinary `compose` remains independent of
Evolution. Current Beasts remains pinned to full B1 and is not migrated here.

## Existing Drift and this add-on

The existing `composition/drift.cairo` is unchanged. Its helper computes epoch
`floor(max(execution_block - 10, 0) / 43200)` and `DriftClock.day = epoch + 1`;
43200 is a placeholder block count for a day. `DriftClock` supplies that day and
the day/week/month hashes. A monthly rhythm replacement is selected when the
month index is positive and its hash-derived `m % 3 != 0`; weekly same-count
channel rotation uses the hash-derived `w % 4 != 0`. These are hash gates, not
fixed two-of-three or three-of-four cycles. A daily knob changes key-plan/episode
direction or nudges tempo by ±2/4 BPM.
Nothing accumulates: each period's rendition is reconstructed from its context.
These are discrete period changes, not a continuous audio stream.

Evolution adds two independent behaviors:

- A supplied actual staff block and its hash seed bounded note interpretation:
  tempo, velocity and octave ornaments. This can differ at every staff.
- Sparse milestone hashes can permanently enable extra written roles. Each
  feature's first successful roll remains enabled in later contexts under the
  same immutable recipe, config, group and class. A later unlock cannot evict a
  previously unlocked role. Authorized patches before freezing those bindings
  can change that interpretation.

## Caller boundary and replay

`compose_staff(inputs, preset, config, context)` returns complete matching MIDI
and TinySynth settings. The pure class reads no chain state. Its caller supplies
birth, group, actual staff `N/H(N)` and every eligible milestone hash. A canonical
caller can choose Live `current - 10` once to satisfy Starknet hash availability;
the library subtracts no further lag. Unreadable/missing canonical hashes are a
caller error, not a reason to substitute different blocks or hashes.

Milestones are `birth + A*2^k`, `k=0..7`, inclusive at the staff. Birth100 with
A10 has eligible blocks110,120,140 at staff140; replay at110 uses only110. The
library checks prebirth, exact prefix, bounds and nonzero hashes. It cannot
authenticate caller-supplied hashes: integrating callers must do so themselves.
Identical context deterministically reproduces the same finite MIDI and settings;
this is neither historical ownership-state replay nor uninterrupted playback.
No history scan, keeper, period transaction or timestamp service is introduced.

`compose` is the Original/as-written path. SoundCheck through `compose_staff`
still rejects prebirth, but intentionally returns its performance rendition
without inspecting unused temporal config/hashes. A caller that needs those
validated independently must enforce that policy before this call.

## Bounds and costs

The finite reference permits eight milestone opportunities and at most five
eligible extra roles, restricted by actual written-role capacity. Each feature
checks its milestones until its first success: at most forty feature-roll hashes
plus one staff-domain hash. Milestone probabilities and bounds are explicit in
`EvolutionConfig`; unlocks are not guaranteed. New structural opportunities end
after the eighth milestone, while staff interpretation continues. Note changes
remain bounded by the config and supported MIDI pitch range.

The measured composer grows from 75,315 to 81,319 CASM felts (6,004 additional;
601 below the 81,920 cap); generator remains 12,751. Historical hash acquisition
and availability belong to the integrating caller, which needs at most one staff
and eight milestone hashes and may reuse overlapping anchors. These counts are
not a claim about full manager/metadata rendering gas.

The downstream Beasts manager stays pinned to immutable full B1
`eebed3a773283d4e103c1042ac372ba4bbf50f61`, including Evolution. This split does
not modify Beasts source, its pin or its fixtures. Consumers of `compose_staff`
need both the base reference and this optional add-on.
