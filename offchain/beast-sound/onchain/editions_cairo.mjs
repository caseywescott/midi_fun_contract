// Generate beasts/beast_composer/src/composition/editions_data.cairo: the tables of the Monthly
// Track Editions engine (src/editions_lite.js) for its Cairo port (editions.cairo): the 75 species
// records (tonic and the opening of the Genesis theme), the scales and the four styles.
//   node onchain/editions_cairo.mjs && scarb fmt   # write the file (scarb fmt formats it as committed)
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { engine as ENGINE } from '../src/index.js';
import { createEngineV11 } from '../src/engine_v11.js';
import * as LAB from '../src/lab.js';
import { SCALES, STYLES } from '../src/editions_lite.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const OUT = here + '../../../beasts/beast_composer/src/composition/editions_data.cairo';

// ── the species records, as the editions page builds them (onchain/editions-demo.mjs) ──
export function speciesRecords() {
  const V11E = createEngineV11(ENGINE);
  return Array.from({ length: 75 }, (_, k) => {
    const id = k + 1, tier = Math.floor((k % 25) / 5) + 1, type = Math.floor(k / 25);
    const o = LAB.genesisMidi(id, false, ENGINE, V11E);
    return { id, tier, type, tonicPc: o.result.params.tonic_keynum % 12, degrees: o.result.form.theme.degrees };
  });
}

const span = (xs) => '[' + xs.join(', ') + '].span()';
// small values, 4 bits each from the low end (a cell's eighths, a progression's roots)
const nibbles = (xs) => { if (xs.length > 7 || xs.some((x) => x < 1 && x !== 0 || x > 15)) throw new Error('nibbles ' + xs); return xs.reduce((v, x, i) => v + x * 16 ** i, 0); };
// an accompaniment or bass event: offset | duration << 11 | voice << 22 | (velocity delta + 32) << 26
const event = ([off, d, voice, dv]) => {
  if (off >= 2048 || d >= 2048 || voice >= 16 || dv < -32 || dv > 31) throw new Error('event ' + [off, d, voice, dv]);
  return off + d * 2048 + voice * 2 ** 22 + (dv + 32) * 2 ** 26;
};
// a percussion event: offset | drum note << 11 | (velocity delta + 64) << 18
const hit = ([off, note, dv]) => {
  if (off >= 2048 || note >= 128 || dv < -64 || dv > 63) throw new Error('hit ' + [off, note, dv]);
  return off + note * 2048 + (dv + 64) * 2 ** 18;
};
const figures = (fs, f) => '[' + fs.map((x) => span(x.map(f))).join(', ') + '].span()';

function main() {
  const SP = speciesRecords();
  const L = [];
  const w = (s = '') => L.push(s);
  w('//! Tables of the Monthly Track Editions engine (editions.cairo), generated from');
  w('//! offchain/beast-sound/src/editions_lite.js by offchain/beast-sound/onchain/editions_cairo.mjs. Do not');
  w('//! edit: change the source and rerun the generator.');
  w('');
  for (const s of SP) { if (s.degrees.length < 6) throw new Error('short theme ' + s.id); for (const d of s.degrees.slice(0, 6)) if (d < -7 || d > 7) throw new Error('degree ' + d + ' (editions.cairo places the motif with one octave step)'); }
  const packed = SP.map((s) => { let v = BigInt(s.tonicPc); s.degrees.slice(0, 6).forEach((d, i) => { v |= BigInt(d + 8) << BigInt(4 + 4 * i); }); return '0x' + v.toString(16); });
  w('/// Species 1..75: tonic pitch class (bits 0-3), then the first 6 Genesis theme degrees + 8');
  w('/// (4 bits each, from bit 4).');
  w(`pub const SPECIES: [u32; 75] = [${packed.join(', ')}];`);
  w('');
  w('/// Scales: major, minor, harmonic minor, Lydian, Phrygian.');
  w(`pub const SCALES: [[u32; 7]; ${SCALES.length}] = [${SCALES.map((s) => '[' + s.join(', ') + ']').join(', ')}];`);
  w('');
  w('#[derive(Copy, Drop)]');
  w('pub struct Style {');
  w('    pub num: u32,');
  w('    pub den: u32,');
  w('    pub bpm_lo: u32,');
  w('    pub bpm_hi: u32,');
  w('    pub modes: Span<u32>,');
  w('    pub chord_bars: u32,');
  w('    /// melody rhythm cells and the phrase-end ones: eighths, 4 bits each from the low end');
  w('    pub cells: Span<u32>,');
  w('    pub end: Span<u32>,');
  w('    /// the figures a purchase picks from, events per bar: offset | duration << 11 | voice (bass:');
  w('    /// tone) << 22 | (velocity delta + 32) << 26');
  w('    pub accomps: Span<Span<u32>>,');
  w('    pub basses: Span<Span<u32>>,');
  w('    /// percussion figures: offset | drum note << 11 | (velocity delta + 64) << 18');
  w('    pub percs: Span<Span<u32>>,');
  w('    /// [lead, counter (unused), accomp, bass, pad] x [Magic, Hunter, Brute]');
  w('    pub palette: Span<u8>,');
  w('    /// progressions: four chord roots (scale degrees), 4 bits each from the low end');
  w('    pub progs: Span<u32>,');
  w('}');
  w('');
  w('/// How many styles the calendar takes in turn.');
  w(`pub const STYLE_COUNT: u32 = ${STYLES.length};`);
  w('');
  // the styles' tables as 32-bit values (scalars, then each list as its length and items), packed 7 to
  // a felt from the low end; each style starts on a fresh felt at STYLE_AT[s]
  const words = [], at = [];
  for (const S of STYLES) {
    const v = [S.num, S.den, S.bpm[0], S.bpm[1], S.chordBars];
    const list = (xs) => { v.push(xs.length, ...xs); };
    list(S.modes); list(S.cells.map(nibbles)); list(S.end.map(nibbles));
    for (const f of S.accomps) list(f.map(event));
    for (const f of S.basses) list(f.map(event));
    for (const f of S.percs) list(f.map(hit));
    list(S.palette.flat()); list(S.progs.map(nibbles));
    if (S.accomps.length !== 4 || S.basses.length !== 3 || S.percs.length !== 2) throw new Error('figure counts ' + S.key);
    at.push(words.length);
    for (let i = 0; i < v.length; i += 7) words.push('0x' + v.slice(i, i + 7).reduce((acc, x, k) => acc | (BigInt(x) << BigInt(32 * k)), 0n).toString(16));
  }
  at.push(words.length);
  w('/// The styles: ' + STYLES.map((s) => s.key).join(', ') + '.');
  w('/// Their tables as 32-bit values packed 7 to a felt from the low end (CASM size: data, not code):');
  w('/// num, den, bpm_lo, bpm_hi, chord_bars, then modes, cells, end, the 4 accompaniment, 3 bass and 2');
  w('/// percussion figures, palette and progressions, each as its length then its items. Style s starts');
  w('/// at word STYLE_AT[s].');
  w(`const STYLE_DATA: [felt252; ${words.length}] = [${words.join(', ')}];`);
  w(`const STYLE_AT: [u32; ${at.length}] = [${at.join(', ')}];`);
  w('');
  w('#[derive(Drop)]');
  w('struct Reader {');
  w('    data: Span<felt252>,');
  w('    pos: u32,');
  w('    word: u256,');
  w('    left: u32,');
  w('}');
  w('');
  w('/// The next 32-bit value.');
  w('#[inline(never)]');
  w('fn read(ref r: Reader) -> u32 {');
  w('    if r.left == 0 {');
  w('        r.word = (*r.data.at(r.pos)).into();');
  w('        r.pos += 1;');
  w('        r.left = 7;');
  w('    }');
  w('    let (q, v) = DivRem::div_rem(r.word, 0x100000000);');
  w('    r.word = q;');
  w('    r.left -= 1;');
  w('    v.try_into().unwrap()');
  w('}');
  w('');
  w('/// A list: its length, then its items.');
  w('#[inline(never)]');
  w('fn read_list(ref r: Reader) -> Span<u32> {');
  w('    let n = read(ref r);');
  w('    let mut out: Array<u32> = array![];');
  w('    for _ in 0..n {');
  w('        out.append(read(ref r));');
  w('    }');
  w('    out.span()');
  w('}');
  w('');
  w('/// `n` lists.');
  w('fn read_lists(ref r: Reader, n: u32) -> Span<Span<u32>> {');
  w('    let mut out: Array<Span<u32>> = array![];');
  w('    for _ in 0..n {');
  w('        out.append(read_list(ref r));');
  w('    }');
  w('    out.span()');
  w('}');
  w('');
  w('/// Style `s` (0..STYLE_COUNT), unpacked.');
  w('#[inline(never)]');
  w('pub fn style(s: u32) -> Box<Style> {');
  w('    let mut r = Reader { data: STYLE_DATA.span(), pos: *STYLE_AT.span().at(s), word: 0, left: 0 };');
  w('    let (num, den, bpm_lo, bpm_hi, chord_bars) = (read(ref r), read(ref r), read(ref r), read(ref r), read(ref r));');
  w('    let modes = read_list(ref r);');
  w('    let cells = read_list(ref r);');
  w('    let end = read_list(ref r);');
  w('    let accomps = read_lists(ref r, 4);');
  w('    let basses = read_lists(ref r, 3);');
  w('    let percs = read_lists(ref r, 2);');
  w('    let mut palette: Array<u8> = array![];');
  w('    for x in read_list(ref r) {');
  w('        palette.append((*x).try_into().unwrap());');
  w('    }');
  w('    let progs = read_list(ref r);');
  w('    BoxTrait::new(');
  w('        Style {');
  w('            num, den, bpm_lo, bpm_hi, modes, chord_bars, cells, end, accomps, basses, percs,');
  w('            palette: palette.span(), progs,');
  w('        },');
  w('    )');
  w('}');
  writeFileSync(OUT, L.join('\n') + '\n');
  console.log('wrote', OUT);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
