import { validateBRR } from './brr.js';

export const DEFAULT_ENVELOPE = { attack: 0.008, decay: 0.18, sustain: 0.7, release: 0.15 };
export const integer = (v, min, max) => Number.isInteger(v) && v >= min && v <= max;
export function envelope(value = {}) {
  const result = { ...DEFAULT_ENVELOPE, ...value };
  for (const k of ['attack', 'decay', 'release']) {
    if (!Number.isFinite(result[k]) || result[k] < 0 || result[k] > 10) throw new Error(`Invalid envelope ${k}`);
  }
  if (!Number.isFinite(result.sustain) || result.sustain < 0 || result.sustain > 1) throw new Error('Invalid sustain');
  return result;
}
export function fromBase64(text) {
  if (typeof text !== 'string' || !/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(text)) throw new Error('Invalid sample base64');
  return Uint8Array.from(atob(text), (ch) => ch.charCodeAt(0));
}
export function validateBank(bank) {
  if (bank?.format !== 'BSBRR1' || !Array.isArray(bank.samples) || !Array.isArray(bank.instruments) || bank.samples.length > 256 || bank.instruments.length > 256) throw new Error('Expected BSBRR1 bank (up to 256 samples/instruments)');
  if (bank.name !== undefined && typeof bank.name !== 'string') throw new Error('Invalid bank name');
  // An evaluation bank (local listening only) may exceed the onchain 64 KiB; the onchain build refuses it.
  const cap = bank.evaluation === true ? 8 << 20 : 65536;
  let size = 0;
  for (const s of bank.samples) {
    const bytes = fromBase64(s.data);
    size += bytes.length;
    if (size > cap) throw new Error(cap === 65536 ? 'BRR bank exceeds 64 KiB' : 'Evaluation bank exceeds 8 MiB');
    validateBRR(bytes, s.loopStart);
    if (!integer(s.rate, 12000, 32000)) throw new Error('Invalid sample rate');
    // Cached PCM playback must have an independent loop entry.
    if (s.loopStart !== null && (bytes[s.loopStart / 16 * 9] & 12)) throw new Error('Loop entry must use filter 0');
  }
  const ids = new Set(), slots = new Map();
  for (const inst of bank.instruments) {
    if (typeof inst.id !== 'string' || !inst.id || ids.has(inst.id)) throw new Error('Instrument ids must be unique strings');
    ids.add(inst.id);
    if (!integer(inst.sample, 0, bank.samples.length - 1) || !integer(inst.rootNote, 0, 127) || !Number.isFinite(inst.tuneCents) || Math.abs(inst.tuneCents) > 1200 || !Number.isFinite(inst.volume) || inst.volume < 0 || inst.volume > 1) throw new Error(`Invalid instrument ${inst.id}`);
    const drum = inst.drum !== undefined;
    if (!integer(drum ? inst.drum : inst.program, 0, drum ? 127 : 128) || (drum && inst.program !== undefined)) throw new Error('Choose one MIDI program (0–128) or drum key (0–127)');
    // key zones: instruments may share a slot when each names its key range and the ranges are disjoint
    if (inst.keys !== undefined && !(Array.isArray(inst.keys) && inst.keys.length === 2 && integer(inst.keys[0], 0, 127) && integer(inst.keys[1], inst.keys[0], 127))) throw new Error(`Invalid key range for ${inst.id}`);
    const slot = `${drum ? 'd' : 'p'}${drum ? inst.drum : inst.program}`, [lo, hi] = inst.keys ?? [0, 127];
    for (const [l, h] of slots.get(slot) ?? []) if (lo <= h && l <= hi) throw new Error(`Duplicate MIDI mapping ${slot}`);
    slots.set(slot, [...(slots.get(slot) ?? []), [lo, hi]]); envelope(inst.envelope);
  }
  return bank;
}
