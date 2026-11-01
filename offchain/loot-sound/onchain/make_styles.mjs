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
];
const HOME_MODE = { major: 0, minor: 1, lydian: 3 };

const out = DEFS.map(([key, label, noun, desc, src, home, bpm, progs]) => {
  const S = from(src);
  return {
    key, label, noun, desc, source: src, home, num: S.num, den: S.den, bpm, modes: [HOME_MODE[home]], chordBars: progs.some((p) => p.split('-').length === 8) ? 1 : S.chordBars,
    cells: S.cells, end: S.end, accomps: S.accomps, basses: S.basses, percs: S.percs, palette: S.palette,
    progs: progs.map((p) => p.split('-')),
  };
});
for (const s of out) {
  if (s.progs.length !== 16) throw new Error(s.key + ': ' + s.progs.length + ' progressions');
  if (s.chordBars === 2 && s.progs.some((p) => p.length !== 4)) throw new Error(s.key + ': 8-chord progressions need one chord a bar');
}
const here = new URL('../src/loot_styles.js', import.meta.url);
writeFileSync(here, '// Generated by onchain/make_styles.mjs from Beasts v1.0.1 edition styles: do not edit.\nexport const STYLES = ' + JSON.stringify(out) + ';\n');
console.log(out.map((s) => `${s.key} (${s.source}, ${s.home}, ${s.num}/${s.den}, ${s.chordBars} bar/chord)`).join('\n'));
