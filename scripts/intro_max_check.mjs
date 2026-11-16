// The editions' intro cap (loot_editions.js INTRO_MAX_S): introBars = max(num == 2 ? 2 : 1, min(introBars,
// floor(INTRO_MAX_S / (num * (4 / den) * 60 / bpm)))), with introBars at most 4. editions.cairo uses the
// exact integer floor(3 * bpm * den / (160 * num)); the float expression can land just under an integer
// where the exact value is one (6/8 at 280 BPM: 6.999...), so this checks min(4, cap) agrees for every
// style's meter at every bpm 1..1000 (a superset of the reachable tempos), and lists the reachable ones.
//   node scripts/intro_max_check.mjs
import { STYLES } from '../offchain/loot-sound/src/loot_styles.js';
import { INTRO_MAX_S, SLOW_TOP, QUICKER } from '../offchain/loot-sound/src/loot_editions.js';
if (INTRO_MAX_S !== 4.5) throw new Error('INTRO_MAX_S changed: update the integer form');
const meters = [...new Set(STYLES.map((S) => S.num + '/' + S.den))].map((m) => m.split('/').map(Number));
let n = 0, raw = 0;
for (const [num, den] of meters) for (let bpm = 1; bpm <= 1000; bpm++) {
  const js = Math.floor(INTRO_MAX_S / (num * (4 / den) * 60 / bpm)), cairo = Math.floor((3 * bpm * den) / (160 * num));
  if (js !== cairo) raw++;
  if (Math.min(4, js) !== Math.min(4, cairo)) throw new Error(`${num}/${den} at ${bpm} BPM: js ${js}, integer ${cairo}`);
  n++;
}
// the tempos a purchase can reach: the genome's (any in the style's range), the purchase's -4..4, quicker
const reach = STYLES.map((S) => { const set = new Set(); for (let b = S.bpm[0]; b <= S.bpm[1]; b++) for (const d of [-4, -2, 0, 2, 4]) for (const q of S.bpm[1] <= SLOW_TOP ? QUICKER : [0]) set.add(Math.round((b + d) * (100 + q) / 100)); return [S.key, S.num + '/' + S.den, Math.min(...set), Math.max(...set)]; });
console.log('intro cap: min(4, cap) exact for', meters.map((m) => m.join('/')).join(' '), 'at bpm 1..1000 (' + n + ' cases; the raw floor differs in ' + raw + ', all at caps above 4)');
console.log('reachable tempos:', reach.map((r) => r.join(' ')).join('; '));
