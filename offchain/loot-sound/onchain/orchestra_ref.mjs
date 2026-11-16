// The Loot lab's orchestration and playback (which bank instrument plays each channel, and what the
// lab does to the file before it plays it), taken verbatim from onchain/loot-lab.mjs so the Cairo port
// is checked against the lab itself: BANK, POOLS, ALIKE, MIX, TOP_SOFT, LEAD_SOFT, SONG, ROUND, the kinds,
// band / choose / moved / stepOf / mix (the lab's own mix, not the editions'), lifted (the pitch lift and
// the CC 7 scaling), notesOf, the editions' volumes (track0's `vol`: MIX times LEAD_SOFT on LEAD_CH), a
// song's LEAD_SOFT on channel 0 (track0's `lf`) and track()'s TOP_SOFT.
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
// a song's lead turn-down: track0's `lf` for a band `orch`
const lf = swap(between('lf = isChip() ? 0 : ', ';\n'), 'lf = isChip() ? 0 : ', 'return ');
if (!src.includes('lifted(o.midi, LIFT[st.kind], lf ? { 0: lf } : null)')) throw new Error('loot-lab.mjs changed: the song lifted call');
const make = new Function('STYLES', `${tables}\n${fns}\n${lifted}\n${notesOf}\nconst DATA = { orch: ORCH };\nconst padOf = (ch, p) => p;\n${track}\nfunction styleVol(key, orch) { const mixOf = DATA.orch.mix[key]; ${vol}; }\nfunction songLead(orch) { ${lf}; }\nreturn { BANK, POOLS, ALIKE, MIX, TOP_SOFT, LEAD_SOFT, SONG, ROUND, SONG_KINDS, ROUND_KINDS, ORCH, mix, stepOf, moved, band, choose, lifted, notesOf, track, styleVol, songLead };`);
export const O = make(STYLES);
export const LIFT = Function(`${between('const LIFT = ', 'function lifted')}; return LIFT;`)();
/** The file the lab plays for a written track: `kind` edition (style `key`: its volumes first), round
 * (lifted), name (lifted, LEAD_SOFT on channel 0), song (LEAD_SOFT on channel 0) or check; `orch` the
 * band; then TOP_SOFT. The programs are as written (the lab sets the band's in the synth: see remap in
 * the parity scripts). */
export function playedRef(kind, midi, orch, key) {
  const lf = kind === 'song' || kind === 'name' ? O.songLead(orch) : 0;
  const m = kind === 'edition' ? O.lifted(midi, 0, O.styleVol(key, orch)) : O.lifted(midi, LIFT[kind], lf ? { 0: lf } : null);
  return O.track({ midi: m, orch }).midi;
}
