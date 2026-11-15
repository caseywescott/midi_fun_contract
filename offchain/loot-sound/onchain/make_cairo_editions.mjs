// Writes loot/loot_composer/src/editions_data.cairo: the tables of the Loot edition engine
// (src/loot_editions.js, styles from src/loot_styles.js) for its Cairo port (editions.cairo).
//   node onchain/make_cairo_editions.mjs && scarb fmt -p loot_composer
// The Roman numeral tables (MAJOR, MINOR, LYDIAN, SUBS) are private to loot_editions.js, so they are
// read from its source text; chordToken checks them against the exported PROGS.
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { STYLES, PROGS, SCALES, COLOURS, WALKS, chordToken, LOW_ACCOMP_STYLES } from '../src/loot_editions.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const OUT = here + '../../../loot/loot_composer/src/editions_data.cairo';

// ── the numeral tables, from the source ──
const src = readFileSync(here + '../src/loot_editions.js', 'utf8');
const grab = (name) => {
  const at = src.indexOf(`const ${name} = {`);
  if (at < 0) throw new Error('no ' + name);
  let i = src.indexOf('{', at), depth = 0, j = i;
  for (; j < src.length; j++) { if (src[j] === '{') depth++; else if (src[j] === '}' && --depth === 0) break; }
  return new Function('return (' + src.slice(i, j + 1) + ');')();
};
const NUMERALS = { major: grab('MAJOR'), minor: grab('MINOR'), lydian: grab('LYDIAN') };
const SUBS = grab('SUBS');
const HOMES = ['major', 'minor', 'lydian'];

// tokens must name numerals one to one within a home, or substitutes by token would differ
for (const h of HOMES) {
  const seen = new Map();
  for (const n of Object.keys(NUMERALS[h])) {
    const t = chordToken(h, n);
    if (seen.has(t)) throw new Error(`${h}: ${n} and ${seen.get(t)} share token ${t}`);
    seen.set(t, n);
  }
}
const tokens = (h, ns) => ns.map((n) => chordToken(h, n));

const span = (xs) => '[' + xs.join(', ') + ']';
const nibbles = (xs) => { if (xs.length > 7 || xs.some((x) => x < 1 || x > 15)) throw new Error('nibbles ' + xs); return xs.reduce((v, x, i) => v + x * 16 ** i, 0); };
const event = ([off, d, voice, dv]) => {
  if (off >= 2048 || d >= 2048 || voice >= 16 || dv < -32 || dv > 31) throw new Error('event ' + [off, d, voice, dv]);
  return off + d * 2048 + voice * 2 ** 22 + (dv + 32) * 2 ** 26;
};
const hit = ([off, note, dv]) => {
  if (off >= 2048 || note >= 128 || dv < -64 || dv > 63) throw new Error('hit ' + [off, note, dv]);
  return off + note * 2048 + (dv + 64) * 2 ** 18;
};
const tok4 = (ts) => { if (ts.length !== 4 || ts.some((t) => t < 0 || t > 254)) throw new Error('tok4 ' + ts); return ts.reduce((v, x, i) => v + x * 256 ** i, 0); };

const L = [];
const w = (s = '') => L.push(s);
w('//! Tables of the Loot edition engine (editions.cairo), generated from offchain/loot-sound/src/');
w('//! loot_editions.js and loot_styles.js by offchain/loot-sound/onchain/make_cairo_editions.mjs. Do not');
w('//! edit: change the source and rerun the generator.');
w('');
w('/// Home scales: ionian, aeolian, harmonic minor, lydian, phrygian.');
w(`pub const SCALES: [[u8; 7]; ${SCALES.length}] = [${SCALES.map(span).join(', ')}];`);
w('/// The colours a chord borrows (colour 0, the home scale, is a placeholder here).');
w(`pub const COLOURS: [[u8; 7]; ${COLOURS.length}] = [${COLOURS.map((c) => span(c ?? [0, 0, 0, 0, 0, 0, 0])).join(', ')}];`);
w('');
// substitutes: token | count << 8 | sub k << (11 + 8k), by home from SUBS_AT[home]
const subs = [], subsAt = [];
for (const h of HOMES) {
  subsAt.push(subs.length);
  for (const [n, xs] of Object.entries(SUBS[h])) {
    if (xs.length > 4) throw new Error('subs ' + n);
    let v = BigInt(chordToken(h, n)) | (BigInt(xs.length) << 8n);
    tokens(h, xs).forEach((t, k) => { v |= BigInt(t) << BigInt(11 + 8 * k); });
    subs.push('0x' + v.toString(16));
  }
}
subsAt.push(subs.length);
w('/// The substitutes an answering phrase may take (loot_editions.js SUBS), by home (major, minor,');
w('/// lydian) from SUBS_AT[home]: token | count << 8 | substitute k << (11 + 8k).');
w(`pub const SUBS: [u64; ${subs.length}] = ${span(subs)};`);
w(`pub const SUBS_AT: [u32; 4] = ${span(subsAt)};`);
w('');
const intro = { major: ['I', 'vi', 'IV', 'V'], minor: ['i', 'VI', 'iv', 'V'], lydian: ['I', 'II', 'I', 'V'] };
w('/// The intro\'s four chords by home, a token a byte from the low end (an intro of N bars plays the');
w('/// last N).');
w(`pub const INTRO_PLAN: [u32; 3] = ${span(HOMES.map((h) => tok4(tokens(h, intro[h]))))};`);
w('');
// walking lines: two 16-bit lines (4 nibbles of offset + 8), line 1 zero when there is one line
const walks = WALKS.map((v) => {
  if (v.length > 2) throw new Error('walks');
  const line = (l) => l.reduce((a, o, i) => { if (o < -8 || o > 7) throw new Error('walk ' + o); return a + (o + 8) * 16 ** i; }, 0);
  return line(v[0]) + (v.length > 1 ? line(v[1]) * 65536 : 0);
});
w('/// WALKS[raw + 6]: one or two lines of 4 offsets + 8 (4 bits each), line 1 in bits 16-31 (0: none).');
w(`pub const WALKS: [u32; 13] = ${span(walks)};`);
w('');
w('#[derive(Copy, Drop)]');
w('pub struct Style {');
w('    pub num: u32,');
w('    pub den: u32,');
w('    pub bpm_lo: u32,');
w('    pub bpm_hi: u32,');
w('    /// the home scale (SCALES) and how many modes the style lists (its draw)');
w('    pub mode: u32,');
w('    pub n_modes: u32,');
w('    pub chord_bars: u32,');
w('    /// 0 major, 1 minor, 2 lydian');
w('    pub home: u32,');
w('    /// 1 arabian, 2 overworld (the mix), 4 the accompaniment may sit an octave lower');
w('    pub flags: u32,');
w('    /// melody rhythm cells and the phrase-end ones: eighths, 4 bits each from the low end');
w('    pub cells: Span<u32>,');
w('    pub end: Span<u32>,');
w('    /// figures: offset | duration << 11 | voice (bass: tone) << 22 | (velocity delta + 32) << 26');
w('    pub accomps: Span<Span<u32>>,');
w('    pub basses: Span<Span<u32>>,');
w('    /// percussion figures: offset | drum note << 11 | (velocity delta + 64) << 18');
w('    pub percs: Span<Span<u32>>,');
w('    /// palette[row * 3 + type]: lead, counter, accomp, bass, pad x three beast types');
w('    pub palette: Span<u32>,');
w('    /// cadences, open and closing: two tokens, a byte each from the low end');
w('    pub cad_open: Span<u32>,');
w('    pub cad_close: Span<u32>,');
w('    /// progressions, two words each: chords 0-3 and 4-7 (0xffffffff: a 4-chord progression), a');
w('    /// token a byte from the low end');
w('    pub progs: Span<u32>,');
w('}');
w('');
w(`pub const STYLE_COUNT: u32 = ${STYLES.length};`);
w('');
const words = [], at = [];
STYLES.forEach((S, si) => {
  const home = HOMES.indexOf(S.home);
  if (home < 0) throw new Error('home ' + S.home);
  const flags = (S.key === 'arabian' ? 1 : 0) | (S.key === 'overworld' ? 2 : 0) | (LOW_ACCOMP_STYLES.includes(S.key) ? 4 : 0);
  if (S.modes.length < 1) throw new Error('modes');
  const v = [S.num, S.den, S.bpm[0], S.bpm[1], S.modes[0], S.modes.length, S.chordBars, home, flags];
  const list = (xs) => { v.push(xs.length, ...xs); };
  list(S.cells.map(nibbles)); list(S.end.map(nibbles));
  if (S.accomps.length !== 4 || S.basses.length !== 3 || S.percs.length !== 2) throw new Error('figure counts ' + S.key);
  for (const f of S.accomps) list(f.map(event));
  for (const f of S.basses) list(f.map(event));
  for (const f of S.percs) list(f.map(hit));
  if (S.palette.length !== 5 || S.palette.some((r) => r.length !== 3)) throw new Error('palette');
  list(S.palette.flat());
  const cad = (xs) => xs.map(([a, b]) => chordToken(S.home, a) + 256 * chordToken(S.home, b));
  list(cad(S.cadences.open)); list(cad(S.cadences.close));
  const progs = [];
  PROGS[si].forEach((p, i) => {
    const q = tokens(S.home, S.progs[i]);
    if (q.join() !== p.join()) throw new Error('PROGS');
    if (p.length === 4) progs.push(tok4(p), 0xffffffff);
    else if (p.length === 8) progs.push(tok4(p.slice(0, 4)), tok4(p.slice(4)));
    else throw new Error('prog length');
  });
  list(progs);
  for (const x of v) if (!Number.isInteger(x) || x < 0 || x > 0xffffffff) throw new Error('word ' + x);
  at.push(words.length);
  for (let i = 0; i < v.length; i += 7) words.push('0x' + v.slice(i, i + 7).reduce((acc, x, k) => acc | (BigInt(x) << BigInt(32 * k)), 0n).toString(16));
});
at.push(words.length);
w('/// The styles: ' + STYLES.map((s) => s.key).join(', ') + '.');
w('/// Their tables as 32-bit values packed 7 to a felt from the low end (CASM size: data, not code):');
w('/// the scalars, then cells, end, the 4 accompaniment, 3 bass and 2 percussion figures, palette,');
w('/// cadences and progressions, each as its length then its items. Style s starts at STYLE_AT[s].');
w(`const STYLE_DATA: [felt252; ${words.length}] = ${span(words)};`);
w(`const STYLE_AT: [u32; ${at.length}] = ${span(at)};`);
w('');
w(`#[derive(Drop)]
struct Reader {
    data: Span<felt252>,
    pos: u32,
    word: u256,
    left: u32,
}

/// The next 32-bit value.
#[inline(never)]
fn read(ref r: Reader) -> u32 {
    if r.left == 0 {
        r.word = (*r.data.at(r.pos)).into();
        r.pos += 1;
        r.left = 7;
    }
    let (q, v) = DivRem::div_rem(r.word, 0x100000000);
    r.word = q;
    r.left -= 1;
    v.try_into().unwrap()
}

/// A list: its length, then its items.
#[inline(never)]
fn read_list(ref r: Reader) -> Span<u32> {
    let n = read(ref r);
    let mut out: Array<u32> = array![];
    for _ in 0..n {
        out.append(read(ref r));
    }
    out.span()
}

/// \`n\` lists.
#[inline(never)]
fn read_lists(ref r: Reader, n: u32) -> Span<Span<u32>> {
    let mut out: Array<Span<u32>> = array![];
    for _ in 0..n {
        out.append(read_list(ref r));
    }
    out.span()
}

/// Style \`s\` (0..STYLE_COUNT), unpacked.
#[inline(never)]
pub fn style(s: u32) -> Box<Style> {
    let mut r = Reader { data: STYLE_DATA.span(), pos: *STYLE_AT.span().at(s), word: 0, left: 0 };
    let (num, den, bpm_lo, bpm_hi) = (read(ref r), read(ref r), read(ref r), read(ref r));
    let (mode, n_modes, chord_bars, home, flags) = (read(ref r), read(ref r), read(ref r), read(ref r), read(ref r));
    let cells = read_list(ref r);
    let end = read_list(ref r);
    let accomps = read_lists(ref r, 4);
    let basses = read_lists(ref r, 3);
    let percs = read_lists(ref r, 2);
    let palette = read_list(ref r);
    let cad_open = read_list(ref r);
    let cad_close = read_list(ref r);
    let progs = read_list(ref r);
    BoxTrait::new(
        Style {
            num, den, bpm_lo, bpm_hi, mode, n_modes, chord_bars, home, flags, cells, end, accomps,
            basses, percs, palette, cad_open, cad_close, progs,
        },
    )
}`);
writeFileSync(OUT, L.join('\n') + '\n');
console.log('wrote', OUT, words.length, 'style words,', subs.length, 'substitutes');
