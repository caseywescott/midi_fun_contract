// BSI1: Beast Sound Instructions, a general fixed-width note format for any music (not only Beast
// canons). 62-bit instructions, 4 per felt, the first in the most significant slot:
//   felt = i0·2^186 + i1·2^124 + i2·2^62 + i3   (unused trailing slots are 0)
//
// instruction = op 2 | payload 60
//   op 2 HEADER  version 8 | ppq 16 | count 24 (instructions in the stream, header included) | 0 12
//   op 1 TEMPO   tempo_us 24 | length_ticks 24 | 0 12   (how long the song lasts, End of Track;
//                0 = until the last note. Older decoders read only tempo_us)
//   op 0 NOTE    time 20 | duration 20 | pitch 7 | velocity 7 | voice 4 | 0 2   (absolute ticks)
// Stream: HEADER, TEMPO, then one NOTE per note in score order.
// Byte-identical to beast_form_to_bsi_felts in beast_v3_sound.cairo.

export const BSI_VERSION = 1;
const OP_NOTE = 0n, OP_TEMPO = 1n, OP_HEADER = 2n;
const SLOT = 62n;
const mask = (bits) => (1n << BigInt(bits)) - 1n;
const field = (v, bits, name) => {
  const x = BigInt(v);
  if (x < 0n || x > mask(bits)) throw new Error(`bsi: ${name} ${v} does not fit ${bits} bits`);
  return x;
};

const header = (count) => (((((OP_HEADER << 8n) | BigInt(BSI_VERSION)) << 16n | 480n) << 24n | field(count, 24, 'count')) << 12n);
const tempo = (us, length) => (((OP_TEMPO << 24n) | field(us, 24, 'tempo_us')) << 24n | field(length, 24, 'length_ticks')) << 12n;
const note = ([time, duration, pitch, velocity, voice]) =>
  ((((((OP_NOTE << 20n | field(time, 20, 'time')) << 20n | field(duration, 20, 'duration')) << 7n | field(pitch, 7, 'pitch')) << 7n
    | field(velocity, 7, 'velocity')) << 4n | field(voice, 4, 'voice')) << 2n);

/** song { notes: [[time, duration, pitch, velocity, voice], ...], tempo_us, length_ticks? } → felts (BigInt). */
export function encodeBsi({ notes, tempo_us, length_ticks = 0 }) {
  const ins = [header(notes.length + 2), tempo(tempo_us, length_ticks), ...notes.map(note)];
  const felts = [];
  for (let i = 0; i < ins.length; i += 4) {
    let f = 0n;
    for (let k = 0; k < 4; k++) f = (f << SLOT) | (ins[i + k] ?? 0n);
    felts.push(f);
  }
  return felts;
}

/** True when felts start with a BSI header (BSN1 starts with a small byte length instead). */
export const isBsi = (felts) => felts.length > 0 && BigInt(felts[0]) >> (3n * SLOT + 60n) === OP_HEADER;

/** felts → { notes, tempo_us, length_ticks? } (length_ticks when the stream carries one). */
export function decodeBsi(felts) {
  const ins = [];
  for (const f of felts) for (let k = 3n; k >= 0n; k--) ins.push((BigInt(f) >> (k * SLOT)) & mask(62));
  const get = (x, shift, bits) => Number((x >> BigInt(shift)) & mask(bits));
  if (ins[0] >> 60n !== OP_HEADER) throw new Error('bsi: missing header');
  const version = get(ins[0], 52, 8), ppq = get(ins[0], 36, 16), count = get(ins[0], 12, 24);
  if (version !== BSI_VERSION) throw new Error('unsupported BSI version ' + version);
  if (ppq !== 480) throw new Error('bsi: unsupported ppq ' + ppq);
  let tempo_us = 500000, length_ticks = 0;
  const notes = [];
  for (let i = 1; i < count; i++) {
    const x = ins[i], op = x >> 60n;
    if (op === OP_TEMPO) { tempo_us = get(x, 36, 24); length_ticks = get(x, 12, 24); }
    else if (op === OP_NOTE) notes.push([get(x, 40, 20), get(x, 20, 20), get(x, 13, 7), get(x, 6, 7), get(x, 2, 4)]);
    else throw new Error('bsi: unknown op ' + op);
  }
  return length_ticks ? { notes, tempo_us, length_ticks } : { notes, tempo_us };
}
