// The Loot lab's orchestration (which bank instrument plays each channel), taken verbatim from
// onchain/loot-lab.mjs so the Cairo port is checked against the lab itself: BANK, POOLS, ALIKE, SONG,
// ROUND, the kinds, and band / choose / moved / stepOf / mix (the lab's own mix, not the editions').
import { readFileSync } from 'node:fs';
import { STYLES } from '../src/loot_styles.js';
const src = readFileSync(new URL('./loot-lab.mjs', import.meta.url), 'utf8');
const between = (a, b) => { const i = src.indexOf(a), j = src.indexOf(b, i); if (i < 0 || j < 0) throw new Error('loot-lab.mjs changed: ' + a); return src.slice(i, j); };
const tables = between('const BANK = ', 'if (Object.keys(POOLS)');
const fns = between('const mix = (a, b) =>', 'const LIFT = ');
const lifted = between('function lifted(u8, by)', 'function track()');
const make = new Function('STYLES', `${tables}\n${fns}\n${lifted}\nconst DATA = { orch: ORCH };\nreturn { BANK, POOLS, ALIKE, SONG, ROUND, SONG_KINDS, ROUND_KINDS, ORCH, mix, stepOf, moved, band, choose, lifted };`);
export const O = make(STYLES);
export const LIFT = Function(`${between('const LIFT = ', 'function lifted')}; return LIFT;`)();
