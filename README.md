# Loot Dungeon Sound

Music for the 30 Loot Dungeon Beasts, as its own contracts. Built on Beast Sound
([caseywescott/midi_fun_contract](https://github.com/caseywescott/midi_fun_contract) `v1.0.1`), which it
depends on by tag and never modifies.

| Track | Engine |
|---|---|
| Species Song, Name Song | the Beasts composer, unchanged (it composes any species id) |
| Sound Check | new: the Beast's band warms up for ten bars (`src/loot_checks.js`) |
| Drift | Casey Drift, unchanged |
| Monthly Track Editions | new: the Beasts edition engine with chromatic harmony |
| Round | new, a candidate for the Species Song: a canon over a chord loop (`src/loot_rounds.js`) |

Sound effects: 0 regular, 1 mega.

## Editions

Twelve styles, one a month in turn, 64 progressions each. Each borrows its meter, figures and presets from a Beasts edition
style and brings its own harmony in Roman numerals (`offchain/loot-sound/onchain/make_styles.mjs`):

- **Realm of Common Tones**: Overworld March, Open Field, Royal Lullaby, Forest Dance, Temple Depths,
  Dungeon Boss. Mode mixture (bVI-bVII-I), chromatic mediants, Lydian II, the minor plagal IV-iv-I.
- **Kingdom of Sweets**: Waltz of the Flowers, Toy March, Grand Adagio, Sugar Plum, Trepak, Arabian
  Night. Applied dominants, diminished sevenths, the Neapolitan and German sixth.

A chord is a scale degree, a colour (the scale it borrows for its bar) and an optional seventh; the
lead, bass and voicings use the bar's colour, so the melody follows chromatic chords.

Spread chords: in some bars the accompaniment's chords are not struck together. They are rolled (the
notes a 64th or so apart and held, upward or downward) or broken into an arpeggio, upward or up and back. Each
arpeggiated bar draws its own subdivision (eighths, sixteenths or, rarely, thirty-seconds:
only one track in four may use them, in one bar of one tune at most; never triplets, in every meter), so the subdivision changes through the track. A purchase draws how many bars do this (20, 35 or 50%) and whether it
leans to rolls, arpeggios or both. The choice is per bar of a tune, so a repeated tune spreads the same
bars. Monthly drift spreads other bars; weekly drift changes the share and the lean. Figures that are
already single notes are left alone. `npm test` checks that a spread bar plays only the struck chord's
notes and that no other part changes.

In the four styles whose accompaniment the bank plays pizzicato (overworld, toy march, sugar plum,
trepak) the accompaniment sits an octave lower on a third of the purchases, and weekly drift moves it
down or back up on about half the weeks.

Walking bass: one purchase in five (of those with a bass) walks for part of the track only: the second
half, the last tune or the third tune. The style's bass figure plays everywhere else. A walk is a note
on every beat (long-short in 6/8, four notes across two bars of 2/4 that share a chord): the chord's
root on the downbeat, chord tones and passing notes between, and a last note a scale step from the next
bar's root. One week of drift in four trades the walk for the figure or back, and a week may move it to
another span. `npm test` checks the downbeat roots, the steps into each next root and that no other
part changes. In the lab, `&walk=1` or `&walk=0` in the URL forces it on or off.

## Rounds

The Beasts composer writes a theme and then repairs each follower note against what is sounding. A
Round puts the harmony first, so the canon fits by construction (`offchain/loot-sound/src/loot_rounds.js`,
JS only so far; integer-only and table-driven for a Cairo port):

1. A chord loop in the Beast's mode (180 four-chord loops: every loop of four chords that starts on the tonic, changes chord at every
   step, turns over with a change and is not two chords twice; 220 eight-chord loops: the written ones
   and each four-chord loop with an answer that closes on the fifth or seventh degree; a mode uses those whose
   chords are all major or minor). The meter goes by family: Magic mostly 6/8 or 3/4, Hunters 4/4 or
   6/8, Brutes 4/4 or 3/4. Each meter has its own rhythm cells, bass figures and percussion. A slot is
   half a bar in 4/4 and 6/8, and a bar in 3/4.
2. One line per canon voice (4 for tiers 1-2, 3 otherwise). At every slot each line holds one member
   of the chord. The members are dealt so the lines sound the whole chord and no line keeps the root or
   the fifth across a chord change.
   Each line has a shape (falling, rising, an arch, close, a valley): the deal leans toward it and the
   line takes each chord tone in its direction.
3. The lines end to end are the theme; its first bar is the species motif, and every line opens with
   the motif's rhythm (even, dotted or snapped, by species) and its two steps.
4. Rhythm cells decorate the lines (passing notes, neighbours, chord skips), busier each time a voice
   comes back to a line. Where a line steps down across a chord change and no other line holds the tone
   it steps to, it may hold its note over the change and resolve a beat late (a suspension).
5. Every voice plays the theme exactly, one loop apart. Half way, a sequence canon (six kinds: falling
   fifths or thirds, rising fifths or steps, two of them on the motif; entries a slot apart), then the round again over a second loop with lines of its own and
   the motif again, and a cadence.

The bass has the root wherever a slot starts (the lines are dealt against it). Between slots its six
figures may take the octave, the chord's third or fifth, or a step into the next root.

Seed 0 is the species' own Round; any other seed is a bought track with its own key, mode, loop and
lines. Casey Drift: the month brings a new loop and new lines, the week trades the instruments between
the voices and changes the contour, a part, the bass figure and the ornaments, and the day turns one
knob (the episode's sequence, the order of entries, or the tempo and articulation). The motif, key, mode
and meter stay. Ornaments grow with the days of drift: 5% more of the notes every 25 days (up to 60% more),
a new figure at days 60, 120, 180 and 270 (mordents, turns, trills, runs into the next note), on every
note of a beat or longer from day 60 and on eighths from day 180. Every voice plays the same ornaments,
so the canon stays exact.

`npm test` checks the notes themselves: the canon and the episode are exact, every strong beat is the
loop's chord, there are no parallel fifths or octaves (bass included), and each drift clock changes
what it says, every suspension is prepared, dissonant and resolved down by step, the second loop
differs from the first, the meter holds through drift, and the bass has the root at every slot.

## Sound Checks

The Beasts composer's Sound Check is one preset playing a scale pattern, a held note and an arpeggio
three times. A Loot Sound Check (`offchain/loot-sound/src/loot_checks.js`, JS only so far) is a routine
for the Beast's whole band (two leads, two plucks, a bass, the kit, the mega double on top): ten bars
of 4/4 in the Beast's key, 17 to 26 seconds.

1. An opening: tuning over a drone, a count-in, or the motif alone and its echo.
2. Three drills drawn without repeats from nine, two bars each: the motif called and answered, the scale
   in thirds, the mode's colour note (Dorian's sixth, Phrygian's second and so on), an arpeggio through
   the cadence, a canon a beat apart, leaps with a swell, a drum break, trills and graces, the motif
   handed round the band.
3. A close: a run into a stinger, a scale that settles, or the motif as a tag.

Take 0 is the species' own Sound Check; any other take is another routine in the same key with the
same motif. `npm test` checks that every pitched note is in the mode, no note collides with itself,
every routine fills its ten bars, and the 30 species and the takes differ.

## Harp glissandi

Editions, Rounds and Sound Checks may have a harp glissando: a diatonic run of 12 to 16 scale steps, a
thirty-second note apart, soft (velocity 43-63), upward or downward, ending where a section ends, and
in one track of three an octave higher. It plays on channel 6 (the harp in the sample banks). A track
has one (11 in 20) or none (9 in 20), never more. Places: in an edition, into the second, third or fourth tune or
into the end; in a Round, into the episode, the return, the cadence or the last chord; in a Sound Check,
at the start, into the first drill, into the close or into the last chord. Weekly drift moves it, turns it or changes
its octave; whether a track has one stays. Species Songs and Name Songs (the Beasts composer) have none.

## Instruments

The lab plays every track through the sample bank by default: ten CC0 VSCO 2 Community Edition
instruments at 16 kHz BRR (midi_fun_contract branch `feat/snes-brr-pipeline`, `onchain/snes/dist-16k/bank.min.js`).
Each edition style maps its lead, accompaniment, bass and pad to bank instruments; songs map their
channels by family. Drums stay on TinySynth's chip kit. The TinyChip presets are a toggle.

## Build the lab

From `offchain/loot-sound/`, with a midi_fun_contract checkout at `v1.0.1` and an onchain-midi-player
checkout (the same inputs as the Beasts labs):

```sh
node onchain/make_styles.mjs <midi_fun_contract>
node onchain/make_species.mjs <midi_fun_contract>
node onchain/loot-lab.mjs <engine .min.js> <onchain-midi-player> <midi_fun_contract> <bank.min.js>
open public/loot-lab.html
```

`src/loot_beasts.js` is a placeholder list (ids 76-105) until the final Beasts are known.
