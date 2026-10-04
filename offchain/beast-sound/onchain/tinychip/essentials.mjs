// Generates the onchain TinyChip runtime: tinychip.js with BANK filled in from the full bank
// (tinysynth-chip.js). Each essential preset's operators get the bank's loudness gain (and any mix trim) folded into the
// levels you hear (g 0 outputs and g > 10 amplitude modulators, as TinyChipBank.install applies it),
// and fields equal to TinySynth's defaults are left out (the runtime fills them back).
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const here = new URL('.', import.meta.url);
// The 20 essentials (bank program numbers). The orchestration pools in tinychip.js use all of them.
export const ESSENTIALS = [0, 1, 2, 3, 4, 12, 15, 18, 20, 21, 23, 28, 33, 34, 38, 50, 51, 53, 54, 61];
const DEFAULTS = { g: 0, w: 'sine', t: 1, f: 0, v: 0.5, a: 0, h: 0.01, d: 0.01, s: 0, r: 0.05, p: 1, q: 1, k: 0 };
const round = (x) => (typeof x === 'number' ? +x.toPrecision(6) : x);

export function loadBank() {
  const ctx = {};
  vm.runInNewContext(readFileSync(new URL('tinysynth-chip.js', here), 'utf8'), ctx);
  return ctx.TinyChipBank;
}

export function bankData(bank = loadBank()) {
  const presets = {};
  for (const id of ESSENTIALS) {
    const pr = bank.PRESETS[id], k = (bank.LOUDNESS[id] ?? 1) * ((bank.MIX_TRIM || {})[id] ?? 1); // loudness match x mix trim
    presets[id] = pr.p.map((o) => {
      const op = { ...o };
      if ((op.g ?? 0) === 0 || op.g > 10) op.v = (op.v ?? DEFAULTS.v) * k;
      return Object.fromEntries(Object.entries(op).filter(([key, val]) => val !== DEFAULTS[key]).map(([key, val]) => [key, round(val)]));
    });
  }
  const drums = Object.fromEntries(Object.entries(bank.DRUMS).map(([key, [, p]]) => [key, p.map((o) => Object.fromEntries(Object.entries(o).map(([k2, v]) => [k2, round(v)])))]));
  return { presets, drums };
}

export function tinychipSource() {
  const src = readFileSync(new URL('tinychip.js', here), 'utf8');
  const marker = '/* BANK */ null';
  if (src.split(marker).length !== 2) throw new Error('tinychip.js: expected one BANK marker');
  return src.replace(marker, JSON.stringify(bankData()).replace(/"(\w+)":/g, '$1:'));
}
