// Writes loot/loot_composer/src/orchestra_data.cairo from the lab's orchestration (orchestra_ref.mjs):
// every instrument pool as one flat byte table. Pools: style s role r (lead, accompaniment, bass, pad)
// = s * 4 + r; Species/Name Song channel c of family t = 4 * STYLES + t * 8 + c; Round/Sound Check
// channel c of family t = 4 * STYLES + 24 + t * 7 + c.     node onchain/make_cairo_orchestra.mjs
import { writeFileSync } from 'node:fs';
import { STYLES } from '../src/loot_styles.js';
import { O } from './orchestra_ref.mjs';
const { ORCH } = O;
const pools = [...STYLES.flatMap((S) => ORCH.pools[S.key]), ...ORCH.songPools.flat(), ...ORCH.roundPools.flat(), ORCH.nameLeads];
const data = pools.flat(), offs = [0]; for (const p of pools) offs.push(offs.at(-1) + p.length);
// u32s 7 to a felt252, item i at bit 32 * (i % 7) of felt i / 7 (read with common::at32)
const packed = (xs) => { const fs = []; for (let i = 0; i < xs.length; i += 7) fs.push('0x' + xs.slice(i, i + 7).reduce((v, w, j) => v + (BigInt(w) << BigInt(32 * j)), 0n).toString(16)); return fs; };
// The lab's volume changes (CC 7 v becomes max(0, min(127, Math.round(v * f - d)))) as one table of
// factors in billionths: Cairo computes max(0, min(127, (v * K + 5e8) / 1e9 - d)), K = round(f * 1e9).
// Contexts: 0 an edition's other channels (MIX), 1 an edition's lead channels LEAD_CH (MIX x LEAD_SOFT x
// LEAD_ALL, then LEAD_DROP), 2 a song's channel 0 (LEAD_SOFT x LEAD_ALL x NAME_SOFT, then LEAD_DROP), 3 a
// Name Song's other channels (NAME_SOFT), 4 TOP_SOFT. An entry is keyed by context, s (the edition's style,
// 1 for a Name Song, 15 any) and program; none found: s 15, then the context's default (LEAD_ALL on the lead
// contexts, else 1). Every (context, style or name, program, CC 7 value) is checked below against the lab's
// own functions, exhaustively.
const D = 1e9, K = (f) => Math.round(f * D);
const LEAD_DROP = ORCH.leadDrop, LEAD_K = K(ORCH.leadAll);
const progs = [...new Set(Object.values(O.BANK))].sort((a, b) => a - b);
const entries = new Map(); // key -> K
const keyOf = (ctx, s, p) => (ctx * 16 + s) * 128 + p;
const put = (ctx, s, p, f) => { const k = keyOf(ctx, s, p); if (entries.has(k) && entries.get(k) !== K(f)) throw new Error('volume table clash'); entries.set(k, K(f)); };
const fOf = (x) => (x === undefined ? 1 : x.f ?? x);
const edVol = (key, ch, p) => { const orch = Array(8).fill(-1); orch[ch] = p; return O.styleVol(key, orch)[ch]; };
const songVol = (named, ch, p) => { const orch = Array(8).fill(-1); orch[ch] = p; return O.songVol(orch, named)[ch]; };
for (const p of progs) {
  // any style: an edition's lead (no MIX); a song's channel 0; a Name Song's others
  const lead = fOf(edVol(STYLES[0].key === 'punkrun' ? STYLES[1].key : STYLES[0].key, 0, p));
  if (K(lead) !== LEAD_K) put(1, 15, p, lead);
  for (const named of [0, 1]) { const f0 = fOf(songVol(!!named, 0, p)); if (K(f0) !== LEAD_K) put(2, named, p, f0); }
  const fn = fOf(songVol(true, 3, p)); if (fn !== 1) put(3, 1, p, fn);
  if (ORCH.topSoft[p]) put(4, 15, p, ORCH.topSoft[p]);
}
STYLES.forEach((S, s) => { const mixOf = ORCH.mix[S.key]; if (!mixOf) return;
  for (const p of progs) { const fl = fOf(edVol(S.key, 0, p)), fo = fOf(edVol(S.key, 2, p));
    if (K(fl) !== (entries.get(keyOf(1, 15, p)) ?? LEAD_K)) put(1, s, p, fl);
    if (fo !== 1) put(0, s, p, fo); } });
// the Cairo lookup, emulated, against the lab for every CC 7 value
const lookup = (ctx, s, p) => entries.get(keyOf(ctx, s, p)) ?? entries.get(keyOf(ctx, 15, p)) ?? (ctx === 1 || ctx === 2 ? LEAD_K : D);
const cairoCc = (v, k, d) => { const x = Math.floor((v * k + D / 2) / D); return x < d ? 0 : Math.min(127, x - d); };
const labCc = (v, x) => (x === undefined ? v : Math.max(0, Math.min(127, Math.round(v * (x.f ?? x) - (x.d ?? 0)))));
let checked = 0;
const check = (what, x, ctx, s, p) => { const k = lookup(ctx, s, p), d = ctx === 1 || ctx === 2 ? LEAD_DROP : 0;
  for (let v = 0; v < 128; v++) { checked++; if (cairoCc(v, k, d) !== labCc(v, x)) throw new Error(`volume ${what} program ${p} at CC 7 ${v}: lab ${labCc(v, x)}, table ${cairoCc(v, k, d)}`); } };
STYLES.forEach((S, s) => { for (const p of progs) for (let ch = 0; ch < 8; ch++) check(S.key + ' ch' + ch, edVol(S.key, ch, p), ch === 0 || ch === 7 ? 1 : 0, s, p); });
for (const named of [0, 1]) for (const p of progs) for (let ch = 0; ch < 8; ch++) check((named ? 'name' : 'song') + ' ch' + ch, songVol(!!named, ch, p), ch === 0 ? 2 : named ? 3 : 0, ch === 0 ? named : named ? 1 : 15, p);
for (const p of progs) check('top', ORCH.topSoft[p], 4, 15, p);
const vols = [...entries].sort((a, b) => a[0] - b[0]).map(([k, v]) => (BigInt(k) << 32n) + BigInt(v));
// a Name Song's lead pool (NAME_LEADS), after the others
const melody = (kinds) => kinds.reduce((m, k, c) => m | (k === 'melody' ? 1 << c : 0), 0);
const monthly = (kinds) => kinds.reduce((m, k, c) => m | ((k === 'melody' || k === 'bass') ? 1 << c : 0), 0);
if (ORCH.songKinds.length !== 8 || ORCH.roundKinds.length !== 7) throw new Error('channel counts changed');
const out = `//! The Loot lab's orchestration tables (onchain/loot-lab.mjs POOLS, SONG, ROUND, ALIKE), as bank programs.
//! Generated by offchain/loot-sound/onchain/make_cairo_orchestra.mjs: do not edit.

pub const STYLE_COUNT: u32 = ${STYLES.length};
pub const SONG_POOL0: u32 = ${STYLES.length * 4};
pub const ROUND_POOL0: u32 = ${STYLES.length * 4 + 24};
/// Song channels whose instrument changes monthly (melody, bass); the others weekly.
pub const SONG_MONTHLY: u32 = ${monthly(ORCH.songKinds)};
pub const ROUND_MONTHLY: u32 = ${monthly(ORCH.roundKinds)};
pub const BELL_A: u8 = ${ORCH.bells[0]};
pub const BELL_B: u8 = ${ORCH.bells[1]};
pub const GLOCK: u8 = ${ORCH.glock};
pub const FLUTE: u8 = ${ORCH.flute};
pub const HARP: u8 = ${ORCH.harp};
/// An accompaniment the composer wrote an octave lower plays this (band(..., low)).
pub const LOW: u8 = ${ORCH.low};
/// A Name Song's lead pool (NAME_LEADS).
pub const NAME_POOL: u32 = ${pools.length - 1};
/// Song channels that are melody voices (choose(..., song): never the theme's instrument).
pub const SONG_MELODY: u32 = ${melody(ORCH.songKinds)};
/// The lab's volume changes on CC 7 (sample banks): (context * 16 + style or name) * 128 + program, then
/// the factor in billionths, at 2^32 (orchestra::vol_k; checked by the generator for every CC 7 value).
pub const VOLS: [u64; ${vols.length}] = [${vols.join(', ')}];
/// LEAD_ALL in billionths, and LEAD_DROP (the lead contexts' defaults).
pub const LEAD_K: u64 = ${LEAD_K};
pub const LEAD_DROP: u8 = ${LEAD_DROP};

/// Where pool i starts in POOL_DATA (and ends: the next), u32s 7 to a felt (common::at32).
pub const POOL_OFFS: [felt252; ${packed(offs).length}] = [${packed(offs).join(', ')}];
/// The pools' programs, flat, u32s 7 to a felt (common::at32).
pub const POOL_DATA: [felt252; ${packed(data).length}] = [${packed(data).join(', ')}];
`;
writeFileSync(new URL('../../../loot/loot_composer/src/orchestra_data.cairo', import.meta.url), out);
console.log(pools.length, 'pools,', data.length, 'programs;', vols.length, 'volume entries,', checked, 'CC 7 values checked');
