// Writes src/loot_styles.js: the Loot Dungeon edition styles. Each borrows its meter, rhythm cells,
// accompaniment, bass and percussion figures and preset palette from a Beasts edition style (so every
// preset it plays already exists in TinyChip), and brings its own harmony: progressions in Roman
// numerals after Realm of Common Tones (mode mixture, chromatic mediants, common-tone pivots) and
// Kingdom of Sweets (applied dominants, diminished sevenths, the Neapolitan and German sixth).
//   node onchain/make_styles.mjs <midi_fun_contract checkout at v1.0.1>
import { writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { join } from 'node:path';

const ref = process.argv[2];
if (!ref) { console.error('usage: node onchain/make_styles.mjs <midi_fun_contract checkout>'); process.exit(2); }
const { STYLES: BEAST } = await import(pathToFileURL(join(ref, 'offchain/beast-sound/src/editions_lite.js')).href);
const from = (key) => { const s = BEAST.find((x) => x.key === key); if (!s) throw new Error('no Beasts style ' + key); return s; };

// [key, label, noun, desc, source style, home ('major' | 'minor' | 'lydian'), bpm, progressions]
const DEFS = [
  ['overworld', 'Overworld March', 'March', 'a heroic brass tune closing on bVI-bVII-I', 'overworld', 'major', [132, 150], [
    'I-bVI-bVII-I', 'I-IV-bVII-I', 'I-bVII-IV-I', 'I-bIII-IV-I', 'bVI-bVII-I-I', 'I-V-bVI-bVII', 'I-iv-bVII-I', 'I-II-IV-I',
    'IV-bVII-I-I', 'I-bVI-IV-bVII', 'I-III-IV-I', 'vi-bVI-bVII-I', 'I-bVII-bVI-bVII', 'I-IV-bVI-bVII', 'I-v-bVII-IV', 'I-bIII-bVII-IV']],
  ['field', 'Open Field', 'Field', 'a Mixolydian drive that never quite cadences, then the long close', 'reel', 'major', [120, 140], [
    'I-bVII-I-bVII-I-bVII-IV-I', 'I-bVII-IV-I-bVI-v-N-V', 'I-bVII-I-IV-bVI-bVII-I-I', 'I-IV-bVII-I-I-IV-bVII-I',
    'I-bVII-I-bVII', 'I-v-bVII-I', 'I-bVII-IV-IV', 'bVI-v-N-V', 'I-IV-I-bVII', 'I-bVII-v-IV', 'IV-bVII-I-I', 'I-bIII-bVII-I',
    'I-bVII-I-I-bVI-bVII-I-I', 'I-v-IV-I-bVI-v-N-V', 'I-I-bVII-IV', 'bVII-IV-I-I']],
  ['lullaby', 'Royal Lullaby', 'Lullaby', 'a slow lullaby that lingers on the dominant and closes IV-iv-I', 'lullaby', 'major', [72, 88], [
    'I-V-IV-V7', 'IV-iv-I-I', 'V-IV-V-V7', 'I-vi-IV-iv', 'ii7-V7-IV-iv', 'V-IV-iv-I', 'I-iii-IV-V7', 'IV-V-iii-vi',
    'ii-V-IV-iv', 'vi-IV-V-V7', 'I-IV-iv-V7', 'V-vi-IV-iv', 'IV-I-V-V7', 'I-V-vi-iv', 'IV-iv-V-I', 'ii7-iv-I-V7']],
  ['forest', 'Forest Dance', 'Dance', 'a Lydian dance on the raised fourth, closing V-II-I', 'hoedown', 'lydian', [132, 150], [
    'I-II-I-II', 'I-II-V-I', 'I-II-vi-II', 'V-II-I-I', 'I-vii-II-I', 'I-iii-II-I', 'vi-II-I-V', 'I-V-II-I',
    'I-II-iii-II', 'II-I-V-I', 'I-vi-II-V', 'I-II-I-V', 'iii-II-I-I', 'I-V-vi-II', 'II-V-I-I', 'I-iii-vi-II']],
  ['temple', 'Temple Depths', 'Depths', 'minor chords pivoting on common tones, a Neapolitan before the dominant', 'dungeon', 'minor', [76, 92], [
    'i-VI-N-i', 'i-iv-VI-V', 'i-III-N-V', 'i-VI-iv-V', 'i-N-V-i', 'iv-i-VI-V', 'i-VII-VI-V', 'i-v-VI-N',
    'i-i-VI-V', 'VI-N-V-i', 'i-iv-N-V', 'i-III-iv-V', 'i-IV-VI-V', 'i-Ger-V-i', 'VI-Ger-V-V', 'i-VI-III-V']],
  ['boss', 'Dungeon Boss', 'Showdown', 'a driving minor battle with Neapolitan and augmented-sixth turns', 'boss', 'minor', [150, 170], [
    'i-N-i-V', 'i-VI-VII-i', 'i-iv-V-i', 'i-N-V-i', 'i-VII-VI-V', 'i-VI-Ger-V', 'i-i-N-V', 'VI-VII-i-i',
    'i-v-VI-V', 'i-III-VII-V', 'iv-V-i-i', 'i-VI-iv-V', 'i-N-VI-V', 'i-VII-i-V', 'VI-N-V-i', 'i-iv-VI-V']],
  ['flowers', 'Waltz of the Flowers', 'Waltz', 'a sweeping waltz through applied dominants and a German sixth', 'waltz', 'major', [150, 170], [
    'I-vi-ii7-V7-I-VI7-ii-V7', 'I-III7-vi-IV-I-II7-V7-I', 'I-I-ii-V7-V7-V7-I-I', 'IV-iv-I-vi-ii-V7-I-I',
    'I-vii°7-I-V7-vi-II7-V-V7', 'I-V7-I-IV-iv-I-V7-I', 'I-iii-IV-iv-I-vi-II7-V7', 'I-VI7-ii-iv-I-Ger-V7-I',
    'I-II7-V7-I', 'I-vi-ii-V7', 'I-III7-vi-V7', 'IV-iv-I-V7', 'I-bVI-V7-I', 'ii7-V7-I-vi', 'I-V7-vi-iv', 'I-vii°7-V7-I']],
  ['toymarch', 'Toy March', 'March', 'a crisp toy-soldier march with secondary dominants', 'march', 'major', [108, 124], [
    'I-V7-V7-I', 'I-IV-V7-I', 'I-II7-V7-I', 'I-vi-ii-V7', 'I-vii°7-V7-I', 'IV-V7-I-I', 'I-III7-vi-V7', 'I-iv-V7-I',
    'ii7-V7-I-I', 'I-VI7-ii-V7', 'I-V-II7-V7', 'vi-II7-V7-I', 'I-IV-Ger-V7', 'I-N-V7-I', 'IV-iv-V7-I', 'I-bVI-V7-I']],
  ['adagio', 'Grand Adagio', 'Adagio', 'a descending adagio, more chromatic toward each cadence', 'chorale', 'major', [66, 80], [
    'I-V-vi-iii-IV-I-ii7-V7', 'IV-iv-I-vi-ii7-Ger-V7-I', 'I-VI7-ii-II7-V7-vi-N-V7', 'vi-iii-IV-I-ii-vii°7-V7-I',
    'I-V-vi-iii', 'IV-I-ii7-V7', 'I-vi-N-V7', 'IV-iv-I-V7', 'I-Ger-V7-I', 'ii7-vii°7-V7-I', 'I-II7-IV-V7', 'vi-III7-IV-V7',
    'I-bVI-ii7-V7', 'I-V-IV-iv', 'I-iii-IV-iv-I-VI7-II7-V7', 'I-V-vi-III7-IV-iv-V7-I']],
  ['sugarplum', 'Sugar Plum', 'Dance', 'a delicate minor dance of diminished sevenths and a German sixth', 'galop', 'minor', [100, 116], [
    'i-iv-V7-i', 'i-VI-Ger-V7', 'i-N-V7-i', 'i-vii°7-i-V7', 'iv-V7-i-i', 'i-VI-iv-V7', 'i-III-iv-V', 'VI-N-V7-i',
    'i-v-VI-V7', 'i-iv-vii°7-V7', 'i-I7-iv-V7', 'i-VII-III-V7', 'i-Ger-V7-i', 'iv-VI-N-V7', 'i-i-iv-V7', 'i-VI-vii°7-V7']],
  ['trepak', 'Trepak', 'Trepak', 'a stamping Russian dance, fast and bright', 'klezmer', 'major', [150, 176], [
    'I-V7-I-V7', 'I-IV-V7-I', 'I-I-V7-I', 'I-ii-V7-I', 'IV-I-V7-I', 'I-vi-II7-V7', 'I-V-I-V', 'I-IV-I-V7',
    'ii-V7-I-I', 'I-iii-IV-V7', 'I-II7-V7-I', 'I-vi-IV-V7', 'vi-ii-V7-I', 'I-V7-vi-V7', 'IV-V7-I-I', 'I-III7-IV-V7']],
  ['arabian', 'Arabian Night', 'Mirage', 'a slow minor drone with a Neapolitan shadow', 'dirge', 'minor', [96, 112], [
    'i-i-iv-i', 'i-VII-VI-V', 'i-iv-i-V', 'i-VI-i-V', 'i-i-VI-V', 'iv-i-VII-i', 'i-N-i-V', 'i-v-iv-i',
    'VI-V-i-i', 'i-VII-i-VII', 'i-iv-VI-V', 'i-i-N-i', 'i-III-iv-i', 'i-v-VI-V', 'iv-VI-V-i', 'i-VI-iv-i']],
  // a thirteenth style, in six: the Beasts tarantella's meter and figures at a chase's pace, Realm harmony in minor
  ['speedrun', 'Speedrun', 'Run', 'a racing 6/8 chase in minor: a whirling tune over a driving bass, bVI-bVII-i at the tape', 'tarantella', 'minor', [160, 184], [
    'i-VI-VII-i', 'i-VII-VI-VII', 'i-VI-III-VII', 'i-iv-VII-III', 'i-VII-i-V', 'VI-VII-i-i', 'i-III-VII-iv', 'i-v-VI-VII',
    'i-VI-iv-V', 'iv-VII-III-VI', 'i-VII-VI-V', 'i-III-VI-VII', 'VI-III-VII-i', 'i-iv-VI-VII', 'i-N-VII-i', 'i-VI-VII-V']],
  // two faster ones in four, from the Beasts speedrun and punk styles (their figures, Realm harmony in major)
  ['dash', 'Dungeon Dash', 'Dash', 'a flat-out 4/4 sprint: racing arpeggios over a driving bass, bVI-bVII-I at the line', 'speedrun', 'major', [190, 212], [
    'I-bIII-bVII-IV', 'I-IV-bVII-I', 'bVI-bVII-I-I', 'I-IV-V-I', 'I-bVII-bVI-IV', 'IV-II-IV-V', 'I-bVII-I-IV', 'bVI-IV-bVII-V', 'IV-bIII-IV-bVII', 'IV-V-bVI-V', 'bVI-IV-V-IV', 'IV-bVII-I-IV', 'I-iii-IV-I', 'IV-bVII-IV-bVII', 'bVI-bVII-bVI-V', 'I-bVII-IV-bVII']],
  ['punkrun', 'Punk Run', 'Riot', 'three chords at full tilt: power chords on every eighth, a pounding bass, the snare on two and four', 'punk', 'major', [196, 220], [
    'I-V-vi-IV', 'I-bVII-IV-I', 'I-bVI-bVII-I', 'vi-IV-I-V', 'I-IV-I-V', 'vi-V-vi-IV', 'IV-bIII-IV-V', 'vi-V-vi-I', 'I-bIII-bVII-IV', 'I-bVII-bVI-IV', 'vi-bVII-bVI-IV', 'vi-bIII-IV-I', 'I-IV-V-bVII', 'vi-v-IV-I', 'I-v-IV-V', 'I-vi-IV-bVII']],
];
// 16 more per style (32 in all), the same idioms with the seventh colours
const MORE = {"overworld": ["I-IV-I-V", "I-bVI-bVII-IV", "IV-V-bVI-bVII", "I-iii-IV-bVII", "I-bVII-IV-V", "vi-IV-bVII-I", "I-IVmaj7-bVII-I", "I-II-bVII-I", "bVI-IV-bVII-I", "I-v-IV-bVII", "I-bIII-IV-V", "IV-bVI-bVII-I", "I-V-vi-bVII", "ii-bVII-I-I", "I-bVI-bIII-bVII", "I-IV-ii-V"], "field": ["I-I7-IV-iv", "I-bVII-bVI-bVII", "I-IV-v-bVII", "IV-I-bVII-I", "I-bVII-IV-bVI-v-IV-bVII-I", "I-v-bVI-bVII", "bVII-I-bVII-I", "I-IV-bVII-IV", "I-bVII-I-IV-bVI-bVII-v-I", "I-iii-bVII-IV", "I-I7-IV-bVII", "vi-bVII-I-I", "I-bVII-ii-IV", "IV-v-bVII-I", "I-bIII-bVII-IV-I-v-bVII-I", "I-IV-I7-IV"], "lullaby": ["IV-V7-iii-vi", "ii7-V7-iii-vi", "IV-iv-iii-vi", "I-IVmaj7-iv-I", "V-iii-IV-iv", "vi-ii7-V7-I", "IVmaj7-iii7-ii7-V7", "I-vi-ii7-V", "IV-I-iv-I", "iii-vi-IV-V7", "V7-vi-IV-iv", "I-Imaj7-IVmaj7-iv", "ii-iv-I-V7", "vi-V-IV-iv", "IV-V-vi-iv", "Imaj7-vi7-ii7-V7"], "forest": ["I-II-vii-I", "vi-V-II-I", "I-iii-V-II", "II-iii-I-I", "I-II-V-V", "vii-II-I-I", "I-vi-V-II", "iii-vi-II-I", "I-II-iii-V", "V-vi-II-I", "I-V-II-vi", "II-I-vi-V", "I-iii-II-V", "vi-II-V-I", "I-II-I-I", "II-vii-I-V"], "temple": ["i-VI-III-iv", "i-iv-i-N", "VI-iv-N-V", "i-III-VI-V", "i-N-VI-V", "iv-VI-Ger-V", "i-i7-iv-V", "i-VII-III-VI", "i-v-iv-V", "VI-III-N-V", "i-IV-iv-V", "iiø7-V7-i-i", "i-VImaj7-iv7-V", "i-III-Ger-V", "iv-iv7-V7-i", "i-N-Ger-V"], "boss": ["i-VII-VI-VII", "i-N-i-VII", "VI-V-i-i", "i-iv-VII-III", "i-V-VI-N", "i-III-iv-V", "i-VI-V-i", "i-v-VI-VII", "iv-N-V-i", "i-VII-N-V", "VI-VII-V-i", "i-Ger-V-V", "i-II-V-i", "i-VI-II-V", "i-iv-N-i", "VI-iv-V-i"], "flowers": ["I-I-IV-IV-V7-V7-I-I", "I-vi-IV-II7-V7-V7-I-I", "I-III7-IV-iv-I-VI7-ii7-V7", "I-Imaj7-vi-vi7-ii7-V7-I-I", "IV-V7-iii-vi-ii-II7-V7-I", "I-V7-vi-III7-IV-I-II7-V7", "I-VI7-II7-V7", "I-iii7-vi7-II7", "IV-Ger-V7-I", "I-vii°7-vi-II7", "iii-VI7-ii-V7", "I-IVmaj7-iv-I", "vi-II7-V7-I", "I-bVI-IV-V7", "Imaj7-vi7-ii7-V7", "I-I7-IV-iv"], "toymarch": ["I-I-V7-I", "I-IV-I-V7", "I-ii-V7-I", "I-II7-V-V7", "I-vi-IV-V7", "IV-I-V7-I", "I-III7-IV-V7", "I-I7-IV-V7", "ii-V7-I-vi", "I-vii°7-I-V7", "vi-ii-V7-I", "I-V7-vi-II7", "I-IV-vii°7-I", "I-bVI-IV-V7", "IV-ii-V7-I", "I-Ger-V7-I"], "adagio": ["I-iii-vi-IV-ii7-V7-I-I", "I-V-vi-III7-IV-I-II7-V7", "vi-IV-I-V-IV-iv-I-V7", "Imaj7-IVmaj7-iii7-vi7-ii7-V7-I-I", "I-VI7-ii-iv-I-N-V7-I", "I-iii-IV-V7", "vi-ii7-V7-I", "IV-iv-V7-I", "I-II7-V7-vi", "IVmaj7-iv-I-V7", "I-vii°7-vi-V7", "ii7-Ger-V7-I", "I-IV-ii7-V7", "vi-IV-N-V7", "I-bVImaj7-IV-V7", "iii7-vi7-ii7-V7"], "sugarplum": ["i-iv-i-V7", "i-VI-N-V7", "i-III-VII-V7", "iv-i-V7-i", "i-iiø7-V7-i", "i-VImaj7-iv-V7", "i-vii°7-VI-V7", "iv-vii°7-i-V7", "i-II7-V7-i", "i-v-iv-V7", "VI-iv-V7-i", "i-i7-iv7-V7", "i-Ger-V7-V7", "i-III-N-V7", "iv-N-V7-i", "i-VII-VI-V7"], "trepak": ["I-V-I-V7", "I-IV-V-I", "I-vi-V7-I", "IV-V7-I-vi", "I-ii-IV-V7", "I-II7-V-I", "I-I7-IV-V7", "vi-IV-V7-I", "I-V7-IV-V7", "I-iii-vi-V7", "ii-IV-V7-I", "I-IV-ii-V7", "I-V-vi-IV", "IV-I-ii-V7", "I-VI7-ii-V7", "I-vii°7-I-V"], "arabian": ["i-iv-VII-i", "i-VI-VII-i", "i-v-i-v", "i-VII-i-iv", "i-N-VII-i", "iv-v-i-i", "i-iv-v-i", "i-VI-v-i", "VI-VII-i-i", "i-III-VII-i", "i-N-iv-i", "i-iv-N-V", "v-iv-i-i", "i-VII-VI-i", "i-i-v-i", "iv-VII-III-i"]};
MORE.dash = ['I-iii-IV-bVII', 'bVI-II-IV-V', 'IV-bVI-bVII-I', 'bVI-V-bVI-IV', 'I-bIII-IV-bVII', 'IV-bVI-IV-bVII', 'bVI-bIII-IV-bVII', 'bVI-iii-IV-bVII', 'I-bVI-IV-V', 'bVI-bVII-I-IV', 'I-bVII-bVI-V', 'I-bVII-I-V', 'IV-bVII-bVI-IV', 'bVI-v-bVII-I', 'I-bVII-bVI-I', 'bVI-II-IV-I'];
MORE.punkrun = ['I-ii-V-I', 'vi-V-vi-V', 'I-vi-IV-I', 'IV-bVII-bVI-IV', 'I-bIII-IV-V', 'I-vi-IV-V', 'vi-iii-IV-V', 'vi-iii-IV-bVII', 'IV-ii-V-bVII', 'IV-V-vi-IV', 'IV-iii-IV-bVII', 'vi-IV-I-bVII', 'I-iii-IV-V', 'I-IV-bVII-I', 'IV-bIII-IV-I', 'IV-bVI-bVII-V'];
MORE.speedrun = ['i-VII-III-VI', 'i-iv-v-i', 'VI-VII-V-i', 'i-III-iv-VII', 'i-v-iv-VII', 'iv-VI-VII-i', 'i-VI-v-VII', 'III-VII-i-i', 'i-VII-iv-V', 'i-i-VI-VII', 'VI-iv-VII-i', 'i-III-VII-V', 'i-N-V-i', 'VII-VI-VII-i', 'i-iv-III-VII', 'i-VI-III-V'];
for (const d of DEFS) d[7] = [...d[7], ...MORE[d[0]]];
// 32 more per style (64 in all): candidates in order, those a style already has left out
const MORE2 = {
  overworld: "I-bVII-bVI-V I-V-bVII-IV I-bIII-bVI-bVII bVI-bIII-bVII-I I-iv-bVI-bVII I-II-bVII-V IV-I-bVII-I I-bVI-bIII-bVII vi-IV-bVI-bVII I-V-IV-bVII I-bVII-I-V I-IV-bIII-bVII bVII-IV-I-V I-iii-bVI-bVII I-bVI-I-bVII ii-IV-bVII-I I-vi-bVI-bVII I-bIII-bVI-V IV-bVII-bVI-V I-II-bVI-bVII I-bVImaj7-bVII-I I-v-bVI-bVII bVI-bVII-vi-V I-IV-iv-bVII I-V-bIII-IV bIII-IV-bVII-I I-vi-IV-bVII I-bVII-vi-bVI IV-iv-bVII-I I-ii-bVII-V I-III-bVI-bVII I-Imaj7-bVII-IV I-bVI-V-bVII vi-bVII-I-I I-IV-bVII-V I-bIII-ii-bVII bVI-IV-I-V I-iv-I-bVII I-bVII-bIII-IV I-V-bVI-IV I-bVII-V-I I-bIII-I-bVII bVI-I-bVII-I I-IV-bVI-V I-vi-bVII-V I-bVII-ii-V IV-bIII-bVII-I I-iii-IV-V",
  field: "I-bVII-IV-I-v-bVII-IV-I I-v-bVII-IV-I-v-bVI-bVII I-IV-bVII-IV-I-bIII-bVII-I I-bVII-v-IV-bVI-bVII-v-I I-bVII-bVI-bVII I-v-I-bVII I-IV-v-bVII bVII-I-bVII-IV I-bIII-IV-bVII I-bVII-v-bVII IV-I-bVII-v I-v-bVI-bVII I-bVII-IV-v v-bVII-I-I I-IV-bVII-IV I-bVI-bVII-v bVII-v-IV-I I-ii-bVII-I I-bVII-ii-IV IV-v-bVII-I I-v-IV-v I-bIII-bVI-bVII bVI-bVII-v-I I-IV-bIII-bVII I-bVII-bIII-IV v-IV-bVII-I I-vi-bVII-IV I-bVII-vi-v IV-bVII-v-I I-v-ii-bVII bVII-bVI-v-I I-I-v-bVII I-bVII-I-v ii-IV-bVII-I I-IV-I-v bIII-bVII-IV-I I-v-bVII-bVI I-bVI-IV-I v-I-bVII-IV I-bVII-IV-bVI I-bVII-bVI-v I-v-vi-bVII IV-I-v-bVII I-ii-v-bVII bVII-IV-v-I I-bIII-v-bVII I-IV-ii-bVII v-bVI-bVII-I",
  lullaby: "I-IV-I-V7 I-vi-ii7-V7 IV-I-iv-I I-iii-vi-iv I-Imaj7-IV-iv vi-iii-IV-V7 I-V-iv-I ii7-V-I-iv I-IVmaj7-iv-V7 IV-V7-vi-iv I-vi-iii-IV iii-vi-ii7-V7 I-ii7-IV-V7 I-V7-IV-iv IV-iii-ii7-V7 I-iii7-IV-iv vi-V-IV-V7 I-IV-V-vi ii-iv-I-V7 I-vi7-ii7-V7 IV-iv-iii-vi I-V-ii7-iv Imaj7-vi7-ii7-V7 I-iv-I-V7 vi-IV-iv-I I-ii-iii-IV IV-V-I-iv I-bVI-iv-V7 iii-IV-iv-I I-V7-vi-IV ii7-iii7-IV-V7 I-IV-ii7-V7 vi-ii7-IV-iv I-iv7-V7-I IVmaj7-iii7-ii7-V7 I-bVImaj7-iv-I V-vi-ii7-V7 I-iii-ii7-iv I-vi-V-iv IV-ii7-iv-I I-iii-IV-iv vi-iii7-IV-V7 I-V7-iv-I ii7-V7-vi-iv I-IV-iii-iv IV-iv-ii7-V7",
  forest: "I-II-iii-I I-vi-V-II II-iii-I-I I-V-I-II I-II-V-II vi-V-II-I I-iii-V-II I-vii-I-II II-vi-V-I I-II-vi-V iii-vi-II-I I-V-iii-II I-vi-iii-II V-vi-II-I I-II-I-vi vii-II-I-I I-iii-II-V vi-iii-II-I I-II-vii-I II-I-II-V I-V-II-V iii-II-V-I I-vi-I-II V-I-II-I I-II-V-vi vi-II-V-I I-vii-vi-II II-V-vi-I I-iii-I-II V-II-vi-I I-Imaj7-II-I I-II7-V-I I-vi7-II-V Imaj7-II-iii7-II I-II-Vmaj7-I vi7-II7-I-I I-iii7-vi7-II7 I-V-vi-V I-II7-iii-II Imaj7-vi7-II7-V I-Vmaj7-II-I iii7-vi7-II-I I-vi-II7-I II-iii7-vi-I I-II-vi7-II7 Imaj7-II-V-II",
  temple: "i-VI-Ger-V i-iv-i-V i-N-iv-V VI-iv-N-V i-v-iv-V i-III-VI-N i-VII-iv-V iv-N-V-i i-VI-i-N i-iiø7-V-i i-iv7-VII-III VI-III-N-V i-N-VI-V i-i7-iv-V i-VImaj7-N-V III-VI-N-V i-v-N-V i-IV-N-V iv-VI-Ger-V i-VII-III-VI i-VI-VII-V i-iv-III-V N-V-i-i i-III-Ger-V i-vii°7-i-V VI-VII-i-V i-iv-V7-i i-VI-iiø7-V7 i-II-V-i iv-i-N-V i-v-III-iv i-VII-N-V i-ii°-V-i VI-i-N-V i-iv-Ger-V i-III-iiø7-V i-N-i-N iv-VII-III-VI i-VI-N-V7 i-iv-VII-V i-III-VII-V VI-V-i-N i-v-VI-Ger i-iv-iiø7-V i-N-III-V i-VII-VI-N",
  boss: "i-VII-VI-VII i-VI-III-VII i-iv-VII-III i-N-VII-V i-v-iv-V VI-V-i-i i-III-VI-V i-VII-iv-V i-Ger-V-i i-VI-V-i iv-i-V-i i-ii°-V-i i-VI-N-V VII-VI-V-i i-iv-N-V i-v-VII-i i-III-iv-V i-VII-III-V VI-iv-V-i i-i-VI-V i-N-iv-V i-vii°7-i-V7 i-VI-VII-V iv-VII-i-V i-III-N-V i-V-VI-V VI-VII-V-i i-iv-i-VII i-II-V-i i-VII-v-VI III-VII-i-V i-iv7-V7-i i-VI-iv-VII i-v-VI-VII N-V-i-i i-I7-iv-V i-IV-VII-V iv-V-VI-V i-VI-VII-VII i-iv-v-V VI-III-VII-i i-VII-VI-N i-N-III-V i-v-i-V i-III-VII-VI iv-VI-VII-i",
  flowers: "I-I7-IV-iv-I-VI7-ii7-V7 I-vi-II7-V7-iii-VI7-ii7-V7 I-III7-vi-I7-IV-iv-V7-I IV-V7-iii-VI7-ii-Ger-V7-I I-VI7-ii7-V7 I-I7-IV-iv I-iii-vi-II7 IV-I-II7-V7 I-vi-II7-V7 I-III7-vi-II7 ii7-V7-iii-VI7 I-IV-ii7-V7 I-bVI-Ger-V7 vi-II7-ii7-V7 I-V7-I7-IV IV-vii°7-I-V7 I-iii7-VI7-ii I-N-V7-I ii-V7-I-VI7 I-vi7-ii7-V7 I-Imaj7-I7-IV IV-iv-iii-VI7 I-II7-ii7-V7 iii-VI7-ii-V7 I-IVmaj7-vii°7-I I-V7-vi-II7 vi-iii-IV-V7 I-Ger-V7-I IV-V7-iii-vi I-iii-IV-V7 ii7-vii°7-I-I I-VI7-II7-V7 I-iv-I-V7 I-vi-IV-V7 IV-I-ii7-V7 I-III7-IV-iv I-bIII-ii7-V7 I-I7-IV-V7 I-vi-ii-II7 IV-iii-ii7-V7 I-V7-iii-VI7 I-II7-V7-vi vi-VI7-ii-V7 I-iii7-ii7-V7 I-IV-I-V7 ii-II7-V7-I",
  toymarch: "I-V7-I-IV I-I-V7-I I-IV-I-V7 I-II7-V-V7 I-vi-II7-V7 IV-I-V7-I I-V7-vi-II7 I-I7-IV-V7 ii-V7-I-VI7 I-iii-IV-V7 I-VI7-II7-V7 I-IV-II7-V7 vi-ii7-V7-I I-V-I-V7 I-III7-vi-II7 IV-II7-V7-I I-vii°7-I-V7 I-ii7-V7-I I-IV-vii°7-I I-V7-IV-I I-bVI-Ger-V7 ii7-V7-vi-II7 I-vi-IV-V7 I-I7-IV-iv IV-V7-vi-V7 I-II7-ii7-V7 I-V7-I7-IV vi-V7-I-I I-iii-vi-V7 I-IV-V-V7 I-N-I-V7 iii-VI7-ii-V7 I-Imaj7-IV-V7 I-V-vi-V7 IV-iv-I-V7 I-ii-II7-V7 I-VI7-ii7-V7 I-IV-iv-I I-V7-ii-V7 IV-ii-V7-I I-vi-V-V7 I-iii-II7-V7 I-IV-vi-V7 ii-II7-V7-I I-V-IV-V7 I-I-IV-V7",
  adagio: "I-V-vi-iii-IV-iv-ii7-V7 I-iii-vi-I7-IV-iv-V7-I I-Imaj7-vi-IV-ii7-Ger-V7-I vi-V-IV-iii-ii7-N-V7-I I-V-IV-iii-ii7-VI7-II7-V7 IV-iii-ii7-I-vi-II7-V7-I I-iii-vi-IV I-V-IV-V7 vi-V-IV-V7 I-Imaj7-vi-IV I-V-vi-IV IV-iii-ii7-V7 I-iii7-IV-V7 vi-iii-ii7-V7 I-vi-IV-iv I-bVImaj7-N-V7 I-III7-vi-IV IV-I-ii7-Ger I-V-ii7-V7 I-vi7-ii7-V7 iii-vi-ii7-V7 I-IVmaj7-ii7-V7 I-VI7-ii7-V7 IV-V7-iii-vi I-vii°7-vi-IV I-I7-IV-iv vi-IV-ii7-V7 I-V-bVI-V7 I-iii-IV-Ger ii7-V7-Imaj7-vi7 I-II7-ii7-V7 IV-iv-iii-VI7 I-N-V7-I I-vi-iii-IV Imaj7-IVmaj7-ii7-V7 I-V-vi-iv I-bIII-IV-V7 vi-II7-IV-V7 I-V-iii-IV vi-iii7-IV-V7 I-IV-iii-ii7 IV-V-vi-iii I-vi-V-IV I-iii-ii7-V7 ii7-iii7-IV-V7 I-V7-vi-iii",
  sugarplum: "i-vii°7-i-V7 i-iv-i-V7 i-VI-N-V7 i-iiø7-V7-i i-V7-i-iv iv-vii°7-i-V7 i-III-VI-V7 i-N-vii°7-i i-VI-iiø7-V7 i-iv7-V7-i VI-iv-V7-i i-Ger-V7-V7 i-v-iv-V7 i-VII-VI-V7 i-I7-iv-N iv-i-vii°7-i i-III-N-V7 i-VImaj7-iiø7-V7 i-iv-Ger-V7 i-i7-iv-V7 VI-Ger-V7-i i-vii°7-VI-V7 i-N-iv-V7 iv-V7-VI-V7 i-II7-V7-i i-VI-III-V7 i-iv-N-V7 iiø7-V7-i-i i-V7-VI-iv i-VII-iv-V7 i-III-iv-V7 N-V7-i-i i-iv-vii°7-i i-VI-V7-i i-v-VI-N iv-N-V7-i i-i-N-V7 i-VII7-III-V7 i-iv-VI-N i-VI-vii°7-i i-N-Ger-V7 iv-iiø7-V7-i i-III-VII-V7 i-v-iv-N VI-VII-i-V7 i-iv7-vii°7-i",
  trepak: "I-V7-I-I I-IV-I-V I-V-V7-I I-ii-V-I IV-V7-I-V7 I-vi-ii-V7 I-I-IV-V7 I-IV-ii-V7 V7-I-V7-I I-iii-vi-V7 I-V7-IV-V7 ii-V-I-V7 I-vi-V7-I IV-I-ii-V7 I-II7-V-V7 I-IV-V-I vi-IV-V7-I I-V-IV-V7 I-ii7-V7-I I-I7-IV-V7 IV-ii-V7-I I-V7-ii-V7 I-vi-II7-V iii-vi-ii-V7 I-IV-vi-V7 I-V-vi-V7 IV-V-I-V7 I-ii-IV-V7 vi-V7-I-I I-VI7-ii-V7 I-IV-I-I ii7-V7-I-V7 I-iii-ii-V7 I-V-ii-V7 IV-IV-V7-I I-vii°7-I-V7 I-bVII-IV-V7 I-V7-vi-II7 I-IV-V7-V7 I-ii-I-V7 V-I-V7-I I-vi-IV-V I-V7-I-IV IV-I-IV-V7 I-iii-IV-V I-ii7-V-I",
  arabian: "i-i-VII-i i-iv-VII-i i-VI-VII-i i-N-VII-i i-v-i-V iv-i-V-i i-i-iv-V i-VII-VI-i i-iv-i-i VI-VII-i-i i-N-V-i i-v-VI-i i-III-VII-i iv-V-i-i i-VI-N-V i-i-v-i i-VII-iv-i i-iv-N-i VII-VI-V-i i-ii°-i-V i-VI-v-i i-N-iv-i i-III-VI-V iv-VII-i-i i-v-N-i i-i7-iv-i i-VI-iv-V i-VII-v-i N-i-V-i i-iv-v-i i-III-N-i VI-iv-i-V i-IV-i-V i-VII-III-iv i-N-VI-V v-iv-i-i i-iv7-VII-i i-VImaj7-N-i i-VII-i-V i-iv-VII-VI i-VI-i-VII VI-i-VII-i i-N-v-i i-v-VII-i iv-i-N-i i-III-i-V",
};
MORE2.dash = 'IV-bVII-I-V I-v-bVII-IV bVI-iii-IV-V I-bVI-bVII-IV IV-v-bVII-IV I-bVII-IV-V I-V-bVI-IV bVI-bVII-IV-bVII I-IV-bVII-V bVI-IV-bVII-I I-bIII-bVII-V bVI-II-IV-bVII IV-v-bVII-I IV-iv-bVII-I IV-iii-IV-bVII I-iv-bVII-I IV-bIII-IV-V I-bIII-bVII-I IV-II-IV-I I-IV-V-bVII IV-V-bVI-IV IV-iv-bVII-IV bVI-bIII-bVII-IV IV-V-bVI-bVII bVI-V-bVI-V I-iii-IV-V IV-bVII-I-bVII bVI-bVII-I-V bVI-bIII-IV-V IV-bVII-I-I IV-v-bVII-V bVI-IV-bVII-IV bVI-bIII-bVII-I bVI-bVII-I-bVII I-IV-bVII-IV I-v-bVII-I bVI-IV-V-bVII IV-bVI-bVII-V IV-bVI-IV-V bVI-bIII-bVII-V';
MORE2.punkrun = 'I-V-vi-I I-IV-I-IV IV-v-IV-I vi-IV-bVII-IV I-IV-V-I IV-V-IV-bVII vi-bIII-bVII-I I-bIII-bVII-V vi-IV-bVII-V vi-IV-V-bVII vi-IV-I-IV vi-bVI-bVII-I vi-iii-IV-I IV-bVII-IV-I I-v-IV-I IV-V-vi-V vi-V-IV-bVII I-IV-bVII-IV vi-ii-V-I I-bVII-IV-V I-IV-bVII-V vi-V-vi-bVII IV-v-IV-bVII IV-iii-IV-I I-bIII-bVII-I IV-V-vi-I IV-v-IV-V I-ii-V-IV IV-bVII-bVI-V I-V-IV-V I-ii-V-bVII I-IV-I-I I-IV-I-bVII I-iii-IV-bVII I-bVI-bVII-IV IV-bVII-bVI-I I-V-IV-bVII IV-ii-V-IV vi-IV-V-IV I-bIII-IV-bVII';
MORE2.speedrun = 'i-VII-VI-iv i-v-III-VII iv-i-VII-VI i-VI-VII-III III-VI-VII-i i-iv-VII-i i-VII-v-VI VI-V-i-VII i-III-v-VI i-N-VI-VII iv-v-VI-VII i-VII-III-iv i-VI-i-VII VII-III-VI-V i-v-VII-III i-iv-VI-V VI-VII-III-i i-III-iv-V i-VII-i-VI iv-III-VII-i i-VI-N-V i-v-VI-iv III-iv-VII-i i-VII-VI-III i-iv-i-VII VI-III-iv-V i-N-iv-V i-III-VI-V VII-i-VI-VII i-v-i-VII iv-VII-i-i i-VI-iv-VII i-VII-v-i VI-iv-V-i i-III-VII-VI i-iv-v-VII';
const PER_STYLE = 64;
for (const d of DEFS) {
  const have = new Set(d[7]), add = [];
  for (const p of MORE2[d[0]].split(' ')) if (!have.has(p) && add.length < PER_STYLE - d[7].length) { have.add(p); add.push(p); }
  d[7] = [...d[7], ...add];
}
// each style's two-bar cadences: open (its tune ends on the dominant) and close (on the tonic)
const CADENCES = {"overworld": {"open": [["bVI", "bVII"], ["IV", "V"], ["ii", "V"]], "close": [["bVII", "I"], ["V", "I"], ["iv", "I"]]}, "field": {"open": [["IV", "bVII"], ["bVI", "v"], ["v", "bVII"]], "close": [["bVII", "I"], ["v", "I"], ["IV", "I"]]}, "lullaby": {"open": [["ii7", "V7"], ["IV", "V7"], ["iv", "V"]], "close": [["iv", "I"], ["IV", "I"], ["V7", "I"]]}, "forest": {"open": [["vi", "V"], ["II", "V"]], "close": [["II", "I"], ["V", "I"]]}, "temple": {"open": [["N", "V"], ["iv", "V"], ["Ger", "V"]], "close": [["V", "i"], ["V7", "i"], ["iv", "i"]]}, "boss": {"open": [["N", "V"], ["VI", "VII"], ["Ger", "V"]], "close": [["V", "i"], ["VII", "i"], ["N", "i"]]}, "flowers": {"open": [["ii7", "V7"], ["II7", "V7"], ["IV", "V7"]], "close": [["V7", "I"], ["vii°7", "I"], ["iv", "I"]]}, "toymarch": {"open": [["II7", "V7"], ["ii", "V7"], ["IV", "V"]], "close": [["V7", "I"], ["vii°7", "I"], ["IV", "I"]]}, "adagio": {"open": [["ii7", "V7"], ["Ger", "V7"], ["N", "V7"]], "close": [["V7", "I"], ["iv", "I"], ["IV", "I"]]}, "sugarplum": {"open": [["Ger", "V7"], ["N", "V7"], ["iiø7", "V7"]], "close": [["V7", "i"], ["vii°7", "i"]]}, "trepak": {"open": [["ii", "V7"], ["IV", "V7"], ["II7", "V7"]], "close": [["V7", "I"], ["IV", "I"]]}, "arabian": {"open": [["iv", "V"], ["VI", "V"]], "close": [["V", "i"], ["iv", "i"]]}};
CADENCES.dash = { open: [['bVI', 'bVII'], ['IV', 'V'], ['bVII', 'V']], close: [['bVII', 'I'], ['V', 'I'], ['bVI', 'I']] };
CADENCES.punkrun = { open: [['IV', 'V'], ['bVII', 'V'], ['vi', 'V']], close: [['V', 'I'], ['bVII', 'I'], ['IV', 'I']] };
CADENCES.speedrun = { open: [['VI', 'VII'], ['iv', 'V'], ['VII', 'V']], close: [['VII', 'i'], ['V', 'i'], ['VI', 'i']] };
// a style past the first twelve names its family (the first six are Realm, the next six Sweets)
const FAMILY = { speedrun: 'Realm of Common Tones', dash: 'Realm of Common Tones', punkrun: 'Realm of Common Tones' };
// one chord a bar for the marches and dances that moved too slowly
const ONE_BAR = ['toymarch', 'trepak'];
const HOME_MODE = { major: 0, minor: 1, lydian: 3 };

const out = DEFS.map(([key, label, noun, desc, src, home, bpm, progs]) => {
  const S = from(src);
  return {
    key, label, noun, desc, source: src, home, num: S.num, den: S.den, bpm, modes: [HOME_MODE[home]], chordBars: ONE_BAR.includes(key) || progs.some((p) => p.split('-').length === 8) ? 1 : S.chordBars, cadences: CADENCES[key],
    cells: S.cells, end: S.end, accomps: S.accomps, basses: S.basses, percs: S.percs, palette: S.palette,
    progs: progs.map((p) => p.split('-')), ...(FAMILY[key] ? { family: FAMILY[key] } : {}),
  };
});
for (const s of out) {
  if (s.progs.length !== PER_STYLE) throw new Error(s.key + ': ' + s.progs.length + ' progressions');
  const seen = new Set(s.progs.map((p) => p.join('-'))); if (seen.size !== PER_STYLE) throw new Error(s.key + ': a progression repeats');
  if (s.progs.some((p) => p.length !== 4 && p.length !== 8)) throw new Error(s.key + ': a progression is not 4 or 8 chords');
  if (s.chordBars === 2 && s.progs.some((p) => p.length !== 4)) throw new Error(s.key + ': 8-chord progressions need one chord a bar');
}
const here = new URL('../src/loot_styles.js', import.meta.url);
writeFileSync(here, '// Generated by onchain/make_styles.mjs from Beasts v1.0.1 edition styles: do not edit.\nexport const STYLES = ' + JSON.stringify(out) + ';\n');
console.log(out.map((s) => `${s.key} (${s.source}, ${s.home}, ${s.num}/${s.den}, ${s.chordBars} bar/chord)`).join('\n'));
