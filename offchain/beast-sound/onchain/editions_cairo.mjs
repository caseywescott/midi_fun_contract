// Generate beasts/beast_composer/src/composition/editions_data.cairo: the tables of the Monthly Track
// Editions engine (src/editions.js) for its Cairo port (editions.cairo): the 75 species records
// (tonic and the opening of the Genesis theme), grammars, engines, rhythm cells, drum grooves, and
// the integer forms of the engine's floating-point comparisons.
//   node onchain/editions_cairo.mjs && scarb fmt   # write the file (scarb fmt formats it as committed)
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { engine as ENGINE } from '../src/index.js';
import { createEngineV11 } from '../src/engine_v11.js';
import * as LAB from '../src/lab.js';
import * as ED from '../src/editions.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const OUT = here + '../../../beasts/beast_composer/src/composition/editions_data.cairo';

// ── the species records, as the demo builds them (onchain/editions-demo.mjs) ──
export function speciesRecords() {
  const V11E = createEngineV11(ENGINE);
  return Array.from({ length: 75 }, (_, k) => {
    const id = k + 1, tier = Math.floor((k % 25) / 5) + 1, type = Math.floor(k / 25);
    const o = LAB.genesisMidi(id, false, ENGINE, V11E);
    return { id, tier, type, tonicPc: o.result.params.tonic_keynum % 12, degrees: o.result.form.theme.degrees };
  });
}

const QUALS = ['M', 'm', 'o', '+', '7', 'm7', 'M7', 'mM7', 'ø7', 'o7', 'sus'];
const QUAL_TONES = { M: [0, 4, 7], m: [0, 3, 7], o: [0, 3, 6], '+': [0, 4, 8], 7: [0, 4, 7, 10], m7: [0, 3, 7, 10], M7: [0, 4, 7, 11], mM7: [0, 3, 7, 11], 'ø7': [0, 3, 6, 10], o7: [0, 3, 6, 9], sus: [0, 5, 7] };
const SCALE_IDS = Object.keys(ED.SCALES);
const GRAMMAR_IDS = Object.keys(ED.GRAMMARS);
const ENGINE_IDS = ED.ENGINE_LIST; // 0..12, canon is not here
const ACCOMP = ['block', 'strum', 'stab', 'waltz', 'oompah', 'arp16', 'alberti', 'musicbox', 'shuffle', 'bossa', 'tolling', 'chorale', 'phase'];
const BASS = ['root', 'rootfifth', 'waltz', 'octave8', 'boogie', 'pedal', 'bossa', 'sixeight', 'drone', 'riff', 'chorale'];
const GROOVE_IDS = ['none', 'rock', 'halftime', 'drive', 'shuffle', 'march', 'waltz', 'bossa', 'dirge', 'battle', 'battle16', 'minimal'];
const FEELS = ['lyric', 'heroic', 'vocal', 'call', 'slow', 'march', 'waltz', 'compound'];
const COUNTERS = ['none', 'line', 'thirds', 'response', 'phase'];
const ROLES = ['lead', 'counter', 'accomp', 'bass', 'pad'];
const FORM_KIND = { A: 0, B: 1, C: 2, V: 3 };

// the source's tables, read from the module (not exported there)
const src = readFileSync(here + '../src/editions.js', 'utf8');
const evalConst = (name) => { const m = new RegExp('const ' + name + ' = (\\{[\\s\\S]*?\\n\\});').exec(src); if (!m) throw new Error(name); return Function('return ' + m[1])(); };
const CELLS = evalConst('CELLS'), POOLS = evalConst('POOLS'), GROOVES = evalConst('GROOVES');
const ADJ_COUNT = /const ADJ = \[([^\]]*)\]/.exec(src)[1].split(',').length;
const DRUM = { K: 36, S: 38, H: 42, O: 46, T: 43, R: 41 }, VEL = { X: 112, x: 88, o: 52 };

const chordCode = (tok) => { const c = ED.parseChord(tok); return c.r * 16 + QUALS.indexOf(c.q); };
const span = (xs) => '[' + xs.join(', ') + '].span()';

function cells(eighths, feel) {
  const table = ED_CELLS(eighths);
  return table[feel] || table.lyric;
}
const ED_CELLS = (eighths) => CELLS[eighths] || CELLS[8];

// R() < p  <=>  raw < ceil(p * 2^32) for a raw 32-bit draw (raw / 2^32 is exact in a double)
function threshold(p) {
  let t = Math.ceil(p * 4294967296);
  while (t > 0 && (t - 1) / 4294967296 >= p) t--;
  while (t / 4294967296 < p) t++;
  return t;
}

// melody(): dir = prev < target - 2 ? 1 : prev > target + 2 ? -1 : coin, for integer prev:
// prev < ceil(target - 2) and prev > floor(target + 2), with target computed as the source does.
function bounds(lo, hi, half, pos) {
  const phrasePos = pos / half;
  const target = lo + (hi - lo) * (0.35 + 0.45 * Math.sin(Math.PI * phrasePos));
  return [Math.ceil(target - 2), Math.floor(target + 2)];
}

function main() {
  const SP = speciesRecords();
  const L = [];
  const w = (s = '') => L.push(s);
  w('//! Tables of the Monthly Track Editions engine (editions.cairo), generated from');
  w('//! offchain/beast-sound/src/editions.js by offchain/beast-sound/onchain/editions_cairo.mjs. Do not edit:');
  w('//! change the source and rerun the generator.');
  w('');
  // species: tonic pc (4 bits) then degrees[0..8] + 8 (4 bits each), low first
  for (const s of SP) { if (s.degrees.length < 8) throw new Error('short theme ' + s.id); for (const d of s.degrees.slice(0, 8)) if (d < -8 || d > 7) throw new Error('degree ' + d); }
  const packed = SP.map((s) => { let v = BigInt(s.tonicPc); s.degrees.slice(0, 8).forEach((d, i) => { v |= BigInt(d + 8) << BigInt(4 + 4 * i); }); return '0x' + v.toString(16); });
  w('/// Species 1..75: tonic pitch class (bits 0-3), then the first 8 Genesis theme degrees + 8');
  w('/// (4 bits each, from bit 4).');
  w(`pub const SPECIES: [u64; 75] = [${packed.join(', ')}];`);
  w('');
  w('/// Scales by id: ' + SCALE_IDS.join(', ') + '.');
  w(`pub const SCALES: [[i32; 7]; ${SCALE_IDS.length}] = [${SCALE_IDS.map((k) => '[' + ED.SCALES[k].join(', ') + ']').join(', ')}];`);
  w('');
  w('/// Chord qualities by id: ' + QUALS.join(' ') + ' (tones over the root; three-tone ones pad with 0).');
  w(`pub const QUAL_TONES: [[i32; 4]; ${QUALS.length}] = [${QUALS.map((q) => '[' + [...QUAL_TONES[q], 0, 0].slice(0, 4).join(', ') + ']').join(', ')}];`);
  w(`pub const QUAL_LEN: [u32; ${QUALS.length}] = [${QUALS.map((q) => QUAL_TONES[q].length).join(', ')}];`);
  w('');
  // grammars
  w('/// Grammars by id: ' + GRAMMAR_IDS.join(', ') + '. A chord is root * 16 + quality.');
  w('pub fn grammar_scale(g: u8) -> u8 {');
  w(`    *${span(GRAMMAR_IDS.map((k) => SCALE_IDS.indexOf(ED.GRAMMARS[k].scale)))}.at(g.into())`);
  w('}');
  w('pub fn grammar_twelve(g: u8) -> bool {');
  w(`    g == ${GRAMMAR_IDS.indexOf('blues')}`);
  w('}');
  w('pub fn grammar_progs(g: u8) -> Span<Span<u8>> {');
  w('    match g {');
  GRAMMAR_IDS.forEach((k, i) => {
    const progs = ED.GRAMMARS[k].progs.map((p) => span(p.split(' ').map(chordCode)));
    w(`        ${i === GRAMMAR_IDS.length - 1 ? '_' : i} => ${span(progs)},`);
  });
  w('    }');
  w('}');
  w('');
  // engines
  w('/// Engines by id: ' + ENGINE_IDS.join(', ') + ' (canon, edition 0, is not here).');
  w('pub const ENGINE_COUNT: u32 = ' + ENGINE_IDS.length + ';');
  w('/// The curated editions\' engines (edition 0, the canon, is 255).');
  w(`pub const CURATED: [u8; ${ED.CURATED.length}] = [${ED.CURATED.map((c) => (c.engine === 'canon' ? 255 : ENGINE_IDS.indexOf(c.engine))).join(', ')}];`);
  const E = (k) => ED.ENGINES[k];
  const ids = (xs, table) => xs.map((x) => { const i = table.indexOf(x); if (i < 0) throw new Error(x); return i; });
  w('#[derive(Copy, Drop)]');
  w('pub struct EngineDef {');
  w('    pub num: u32,');
  w('    pub den: u32,');
  w('    pub bpm_lo: u32,');
  w('    pub bpm_hi: u32,');
  w('    pub grammars: Span<u8>,');
  w('    pub forms: Span<Span<u8>>,');
  w('    pub accomp: Span<u8>,');
  w('    pub bass: Span<u8>,');
  w('    pub drums: Span<u8>,');
  w('    pub feel: u8,');
  w('    pub counter: u8,');
  w('    /// chords per bar (2: half-bar chords) and bars per chord (1 or 2)');
  w('    pub per_bar: u32,');
  w('    pub chord_bars: u32,');
  w('    pub swing: bool,');
  w('    /// [lead, counter, accomp, bass, pad] x [Magic, Hunter, Brute]');
  w('    pub palette: Span<u8>,');
  w('}');
  w('pub fn engine_def(e: u8) -> EngineDef {');
  w('    match e {');
  ENGINE_IDS.forEach((k, i) => {
    const d = E(k);
    const forms = d.forms.map((f) => span([...f].map((ch) => FORM_KIND[ch] ?? 9)));
    const pal = ROLES.flatMap((r) => d.palette[r]);
    const per = d.chordBars < 1 ? 2 : 1, cb = d.chordBars < 1 ? 1 : d.chordBars;
    w(`        ${i === ENGINE_IDS.length - 1 ? '_' : i} => EngineDef {`);
    w(`            num: ${d.meter[0]}, den: ${d.meter[1]}, bpm_lo: ${d.bpm[0]}, bpm_hi: ${d.bpm[1]},`);
    w(`            grammars: ${span(ids(d.grammars, GRAMMAR_IDS))}, forms: ${span(forms)},`);
    w(`            accomp: ${span(ids(d.accomp, ACCOMP))}, bass: ${span(ids(d.bass, BASS))}, drums: ${span(ids(d.drums, GROOVE_IDS))},`);
    w(`            feel: ${FEELS.indexOf(d.feel)}, counter: ${COUNTERS.indexOf(d.counter)}, per_bar: ${per}, chord_bars: ${cb}, swing: ${!!d.swing},`);
    w(`            palette: ${span(pal)},`);
    w('        },');
  });
  w('    }');
  w('}');
  w('');
  w('/// Role pools for procedural editions: ' + ROLES.join(', ') + '.');
  w('pub fn pool(role: u32) -> Span<u8> {');
  w('    match role {');
  ROLES.forEach((r, i) => w(`        ${i === ROLES.length - 1 ? '_' : i} => ${span(POOLS[r])},`));
  w('    }');
  w('}');
  w('pub const ADJ_COUNT: u32 = ' + ADJ_COUNT + ';');
  w('');
  // cells
  w('/// Rhythm cells (eighths; negative = rest) by bar (6 or 8 eighths) and feel id: ' + FEELS.join(', ') + '.');
  w('pub fn cells(six: bool, feel: u8) -> Span<Span<i32>> {');
  w('    if six {');
  w('        match feel {');
  FEELS.forEach((f, i) => w(`            ${i === FEELS.length - 1 ? '_' : i} => ${span(cells(6, f).map(span))},`));
  w('        }');
  w('    } else {');
  w('        match feel {');
  FEELS.forEach((f, i) => w(`            ${i === FEELS.length - 1 ? '_' : i} => ${span(cells(8, f).map(span))},`));
  w('        }');
  w('    }');
  w('}');
  w('');
  // grooves: per groove the steps per bar and the hits in source order, step | key << 8 | vel << 16
  w('/// Drum grooves by id: ' + GROOVE_IDS.join(', ') + '. (steps per bar, hits in the source\'s order as');
  w('/// step | key << 8 | velocity << 16).');
  w('pub fn groove(g: u8) -> (u32, Span<u32>) {');
  w('    match g {');
  GROOVE_IDS.forEach((k, i) => {
    if (k === 'none') { w(`        0 => (1, [].span()),`); return; }
    const G = GROOVES[k]; let steps = 0; const hits = [];
    for (const [lane, pat] of Object.entries(G)) {
      if (!pat) continue;
      if (steps && pat.length !== steps) throw new Error('lane lengths ' + k);
      steps = pat.length;
      [...pat].forEach((s, j) => { if (VEL[s]) hits.push(j | (DRUM[lane] << 8) | (VEL[s] << 16)); });
    }
    w(`        ${i === GROOVE_IDS.length - 1 ? '_' : i} => (${steps}, ${span(hits)}),`);
  });
  w('    }');
  w('}');
  w('');
  // thresholds
  w('/// R() < p as raw < T (raw a 32-bit draw).');
  for (const [n, p] of [['P012', 0.12], ['P066', 0.66], ['P090', 0.9], ['P050', 0.5], ['P030', 0.3]]) w(`pub const ${n}: u64 = ${threshold(p)};`);
  w('');
  w('/// melody() contour: (A, B) such that prev < target - 2 <=> prev < A and prev > target + 2 <=>');
  w('/// prev > B, for the ranges the engines use (lo, hi) and phrase position pos / half.');
  w('pub fn contour_bounds(lo: i32, half: u32, pos: u32) -> (i32, i32) {');
  const combos = [[61, 77], [66, 82], [64, 79], [67, 84]];
  const arms = [];
  for (const [lo, hi] of combos) for (const half of [4, 6]) {
    const bs = Array.from({ length: half }, (_, p) => bounds(lo, hi, half, p));
    arms.push([`lo == ${lo} && half == ${half}`, `*${span(bs.map(([a, b]) => `(${a}, ${b})`))}.at(pos)`]);
  }
  arms.forEach(([cond, val], i) => w(`    ${i ? '} else if' : 'if'} ${cond} {\n        ${val}`));
  w('    } else {');
  w("        panic!(\"contour range\")");
  w('    }');
  w('}');
  const out = L.join('\n') + '\n';
  writeFileSync(OUT, out);
  console.log('wrote', OUT);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) main();
