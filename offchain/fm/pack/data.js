// The Kankyo patch data, decoded. kankyo-data.js (written by build.mjs from the reference bank) stores each
// instrument as [id, program, lowest root, highest root, volume, [attack, decay, sustain, release], def] and
// each drum as [id, key, volume, def], where a def is the engine's definition with a few shorthands:
//   b: n   start from instrument n's def (decoded) and change only the keys given; a key set to null is removed
//   Z: 'h'   zones computed per root by harpAt (gen.js), roots every 4 semitones from lo to hi
//   t is 'f' (FM) unless given.
import { ROWS, DRUMS } from './kankyo-data.js';
import { GEN } from './gen.js';

function expand(list, lo) {
  const out = [];
  list.forEach((row) => {
    const e = row[row.length - 1], src = e.b !== undefined ? { ...out[e.b].e, ...e } : { ...e };
    for (const k in src) if (src[k] === null) delete src[k];
    delete src.b;
    const d = { t: 'f', ...src }, from = lo ? row[2] : 0;
    if (d.Z) d.zones = Array.from({ length: ((row[3] - from) >> 2) + 1 }, (_, k) => GEN[d.Z](from + 4 * k));
    delete d.Z;
    out.push({ row, e: src, d });
  });
  return out;
}
/** { inst: [{ id, program, lo, hi, volume, env, d }], drums: [{ id, key, volume, d }] } */
export function decode() {
  return {
    inst: expand(ROWS, true).map(({ row: [id, program, lo, hi, volume, env], d }) => ({ id, program, lo, hi, volume, env, d })),
    drums: expand(DRUMS, false).map(({ row: [id, key, volume], d }) => ({ id, key, volume, d })),
  };
}
