# Loot Dungeon Sound

Music for the 30 Loot Dungeon Beasts, as its own contracts. Built on Beast Sound
([caseywescott/midi_fun_contract](https://github.com/caseywescott/midi_fun_contract) `v1.0.1`), which it
depends on by tag and never modifies.

| Track | Engine |
|---|---|
| Species Song, Name Song, Sound Check | the Beasts composer, unchanged (it composes any species id) |
| Drift | Casey Drift, unchanged |
| Monthly Track Editions | new: the Beasts edition engine with chromatic harmony |

Sound effects: 0 regular, 1 mega.

## Editions

Twelve styles, one a month in turn. Each borrows its meter, figures and presets from a Beasts edition
style and brings its own harmony in Roman numerals (`offchain/loot-sound/onchain/make_styles.mjs`):

- **Realm of Common Tones**: Overworld March, Open Field, Royal Lullaby, Forest Dance, Temple Depths,
  Dungeon Boss. Mode mixture (bVI-bVII-I), chromatic mediants, Lydian II, the minor plagal IV-iv-I.
- **Kingdom of Sweets**: Waltz of the Flowers, Toy March, Grand Adagio, Sugar Plum, Trepak, Arabian
  Night. Applied dominants, diminished sevenths, the Neapolitan and German sixth.

A chord is a scale degree, a colour (the scale it borrows for its bar) and an optional seventh; the
lead, bass and voicings use the bar's colour, so the melody follows chromatic chords.

## Build the lab

From `offchain/loot-sound/`, with a midi_fun_contract checkout at `v1.0.1` and an onchain-midi-player
checkout (the same inputs as the Beasts labs):

```sh
node onchain/make_styles.mjs <midi_fun_contract>
node onchain/make_species.mjs <midi_fun_contract>
node onchain/loot-lab.mjs <engine .min.js> <onchain-midi-player> <midi_fun_contract>
open public/loot-lab.html
```

`src/loot_beasts.js` is a placeholder list (ids 76-105) until the final Beasts are known.
