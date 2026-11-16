// The Loot lab's orchestration and playback (which bank instrument plays each channel, and what the
// lab does to the file before it plays it), taken verbatim from onchain/loot-lab.mjs so the Cairo port
// is checked against the lab itself: BANK, POOLS, ALIKE, MIX, TOP_SOFT, LEAD_SOFT, LEAD_ALL, LEAD_DROP,
// NAME_SOFT, NAME_LEADS, SONG, ROUND, the kinds, band / choose / moved / stepOf / mix (the lab's own mix,
// not the editions'), lifted (the pitch lift and the CC 7 scaling), notesOf, the editions' volumes
// (track0's first `vol`), a song's band (track0's `named` / `pools` / `orch`: NAME_LEADS and the name's
// salt on a Name Song) and volumes (its second `vol`), and track()'s TOP_SOFT.
// `padOf` (a bank's fallback for an instrument it lacks) is the identity here: the FM bank the onchain
// files are made for has every instrument; and that bank is a sample bank (not the chip presets), so
// MIX and TOP_SOFT apply.
import { readFileSync } from 'node:fs';
import { STYLES } from '../src/loot_styles.js';
const src = readFileSync(new URL('./loot-lab.mjs', import.meta.url), 'utf8');
const between = (a, b) => { const i = src.indexOf(a), j = src.indexOf(b, i); if (i < 0 || j < 0) throw new Error('loot-lab.mjs changed: ' + a); return src.slice(i, j); };
const swap = (s, a, b) => { if (!s.includes(a)) throw new Error('loot-lab.mjs changed: ' + a); return s.replace(a, b); };
const tables = between('const BANK = ', 'if (Object.keys(POOLS)');
const fns = between('const mix = (a, b) =>', 'const LIFT = ');
const lifted = between('function lifted(u8, by', '// the track as it plays');
const notesOf = between('function notesOf(u8)', 'const ROLES = ');
// track(): the played track from the written one (track0's result passed in), a sample bank
const track = swap(between('function track() {', 'function track0()'), 'function track() {\n  const tr = track0(); if (isChip()) return tr;', 'function track(tr) {');
// the editions' volumes: track0's `vol` for a band `orch` and style `key`
if (!track.includes('const LEAD_CH = ')) throw new Error('loot-lab.mjs changed: LEAD_CH');
const vol = swap(between('const vol = isChip() ? null :', ';\n'), 'const vol = isChip() ? null :', 'return');
// a song's volumes: track0's second `vol` (LEAD_SOFT x LEAD_ALL and LEAD_DROP on channel 0, NAME_SOFT on a
// Name Song's every channel) for a band `orch`, `named` for a Name Song
const songVolAt = src.indexOf('const vol = isChip() ? null :', src.indexOf('const named = st.kind'));
const songVol = swap(swap(src.slice(songVolAt, src.indexOf(';\n', songVolAt)), 'const vol = isChip() ? null :', 'return'), "st.kind === 'name'", 'named');
if (!src.includes('lifted(o.midi, LIFT[st.kind], vol && Object.keys(vol).length ? vol : null)')) throw new Error('loot-lab.mjs changed: the song lifted call');
// a song's band: track0's `named` / `pools` / `orch` lines, for kind 'song' or 'name', name, drift d
const songPools = swap(between('const named = st.kind', ';\n'), "const named = st.kind === 'name'", "const named = kind === 'name'");
const songChoose = swap(swap(between('const orch = choose(pools,', ';\n'), 'x.id, named ? 1 + st.name * 7919 : 1,', 'id, named ? 1 + name * 7919 : 1,'), "day && (st.kind === 'song' || named) ? L.drift2({ id: x.id, prefix: 0, suffix: 0 }, day, anchor) : null", 'd');
const make = new Function('STYLES', `${tables}\n${fns}\n${lifted}\n${notesOf}\nconst DATA = { orch: ORCH };\nconst padOf = (ch, p) => p;\n${track}\nfunction styleVol(key, orch) { const mixOf = DATA.orch.mix[key]; ${vol}; }\nfunction songVol(orch, named) { ${songVol}; }\nfunction songBand(kind, type, id, name, d) { const x = { type }; ${songPools}; ${songChoose}; return orch; }\nreturn { BANK, POOLS, ALIKE, MIX, TOP_SOFT, LEAD_SOFT, LEAD_ALL, LEAD_DROP, NAME_SOFT, NAME_LEADS, SONG, ROUND, SONG_KINDS, ROUND_KINDS, ORCH, mix, stepOf, moved, band, choose, lifted, notesOf, track, styleVol, songVol, songBand };`);
export const O = make(STYLES);
export const LIFT = Function(`${between('const LIFT = ', 'function lifted')}; return LIFT;`)();
/** The file the lab plays for a written track: `kind` edition (style `key`: its volumes first), round
 * (lifted), name (lifted; its volumes), song (its volumes) or check; `orch` the band; then TOP_SOFT. The programs are as written (the lab sets the band's in the synth: see remap in
 * the parity scripts). */
export function playedRef(kind, midi, orch, key) {
  const vol = kind === 'song' || kind === 'name' ? O.songVol(orch, kind === 'name') : null;
  const m = kind === 'edition' ? O.lifted(midi, 0, O.styleVol(key, orch)) : O.lifted(midi, LIFT[kind], vol && Object.keys(vol).length ? vol : null);
  return O.track({ midi: m, orch }).midi;
}
