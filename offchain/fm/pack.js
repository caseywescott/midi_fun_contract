// Compact page form of a BSBRR1 bank. Sample bytes are base91 text (printable ASCII without '"',
// '\' and '<', so it sits in a script string as is: ~1.23 characters per byte, base64 takes 1.33)
// and records are arrays. `unpackBank` rebuilds the exact bank, sample data as base64 again.
const ALPHABET = [...Array(95)].map((_, i) => String.fromCharCode(i + 32)).filter((c) => !'"\\<'.includes(c)).join('');
const N = ALPHABET.length, WIDE = N * N - 8193; // 13-bit values up to WIDE carry a 14th bit
const B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
const ENVELOPE = ['attack', 'decay', 'sustain', 'release'];

export function toBase91(bytes) {
  let out = '', q = 0, n = 0;
  for (const b of bytes) {
    q |= b << n; n += 8;
    if (n > 13) {
      let v = q & 8191;
      if (v > WIDE) { q >>= 13; n -= 13; } else { v = q & 16383; q >>= 14; n -= 14; }
      out += ALPHABET[v % N] + ALPHABET[(v / N) | 0];
    }
  }
  if (n) { out += ALPHABET[q % N]; if (n > 7 || q >= N) out += ALPHABET[(q / N) | 0]; }
  return out;
}

export function fromBase91(text) {
  const out = [];
  let q = 0, n = 0, v = -1;
  for (const c of text) {
    const d = ALPHABET.indexOf(c);
    if (v < 0) { v = d; continue; }
    v += d * N; q |= v << n; n += (v & 8191) > WIDE ? 13 : 14;
    do { out.push(q & 255); q >>= 8; n -= 8; } while (n > 7);
    v = -1;
  }
  if (v >= 0) out.push((q | v << n) & 255);
  return out;
}

function base64(bytes) {
  let out = '';
  for (let i = 0; i < bytes.length; i += 3) {
    const x = bytes[i] << 16 | (bytes[i + 1] ?? 0) << 8 | (bytes[i + 2] ?? 0);
    out += B64[x >> 18] + B64[x >> 12 & 63] + (i + 1 < bytes.length ? B64[x >> 6 & 63] : '=') + (i + 2 < bytes.length ? B64[x & 63] : '=');
  }
  return out;
}

/** Instruments as [id, program or 256 + drum key, sample, rootNote, tuneCents, volume, ...envelope,
 *  lowest key, highest key] (the key range only for a key zone); an evaluation bank adds `1`. */
export function packBank(bank) {
  return [bank.name, bank.samples.map((s) => [s.rate, s.loopStart, toBase91(Buffer.from(s.data, 'base64')), ...(s.smoothing === false ? [0] : [])]),
    bank.instruments.map((i) => [i.id, i.drum === undefined ? i.program : 256 + i.drum, i.sample, i.rootNote, i.tuneCents, i.volume, ...ENVELOPE.map((k) => i.envelope[k]), ...(i.keys ?? [])]), ...(bank.evaluation ? [1] : [])];
}

export function unpackBank([name, samples, instruments, evaluation]) {
  return {
    format: 'BSBRR1', ...(name === null ? {} : { name }), ...(evaluation ? { evaluation: true } : {}),
    samples: samples.map(([rate, loopStart, data, smooth]) => ({ rate, loopStart, data: base64(fromBase91(data)), ...(smooth === 0 ? { smoothing: false } : {}) })),
    instruments: instruments.map(([id, slot, sample, rootNote, tuneCents, volume, ...rest]) => ({
      id, ...(slot > 255 ? { drum: slot - 256 } : { program: slot }), sample, rootNote, tuneCents, volume,
      envelope: Object.fromEntries(ENVELOPE.map((k, j) => [k, rest[j]])), ...(rest.length > 4 ? { keys: rest.slice(4, 6) } : {}),
    })),
  };
}
