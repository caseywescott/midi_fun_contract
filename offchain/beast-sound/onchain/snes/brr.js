// BRR: 16 signed PCM samples per 9-byte block, high nibble first.
// Internal history is half amplitude, matching the DSP's signed 15-bit result.
function predict(filter, a, b) {
  if (filter === 1) return a + ((-a) >> 4);
  if (filter === 2) return 2 * a + ((-3 * a) >> 5) - b + (b >> 4);
  if (filter === 3) return 2 * a + ((-13 * a) >> 6) - b + ((3 * b) >> 4);
  return 0;
}
function sample(n, range, filter, a, b) {
  const residual = range <= 12 ? (n << range) >> 1 : n < 0 ? -2048 : 0;
  const value = Math.max(-32768, Math.min(32767, residual + predict(filter, a, b)));
  return (value << 17) >> 17;
}

export function validateBRR(bytes, loopStart = null) {
  if (!(bytes instanceof Uint8Array) || !bytes.length || bytes.length % 9) throw new Error('BRR must contain complete 9-byte blocks');
  for (let i = 0; i < bytes.length; i += 9) {
    if (!!(bytes[i] & 1) !== (i === bytes.length - 9)) throw new Error('BRR end flag must occur only on the final block');
  }
  if (loopStart !== null && (!Number.isInteger(loopStart) || loopStart < 0 || loopStart % 16 || loopStart >= bytes.length / 9 * 16)) throw new Error('Loop start must be a sample index aligned to 16');
  if (!!(bytes[bytes.length - 9] & 2) !== (loopStart !== null)) throw new Error('BRR loop flag and metadata disagree');
}

export function decodeBRR(bytes, loopStart = null) {
  validateBRR(bytes, loopStart);
  const pcm = new Int16Array(bytes.length / 9 * 16);
  let a = 0, b = 0, pos = 0;
  for (let block = 0; block < bytes.length; block += 9) {
    const range = bytes[block] >> 4, filter = (bytes[block] >> 2) & 3;
    for (let i = 0; i < 16; i++) {
      const packed = bytes[block + 1 + (i >> 1)];
      const n = ((i & 1 ? packed & 15 : packed >> 4) << 28) >> 28;
      const value = sample(n, range, filter, a, b);
      b = a; a = value; pcm[pos++] = value * 2;
    }
  }
  return pcm;
}

// Offline exhaustive filter/range search; greedy quantization uses decoded history.
// Filter 0 at the start AND loop entry makes repeats independent of predictor history.
export function encodeBRR(pcm, loopStart = null) {
  if (!(pcm instanceof Int16Array) || !pcm.length || pcm.length % 16) throw new Error('PCM length must be a nonzero multiple of 16');
  if (loopStart !== null && (!Number.isInteger(loopStart) || loopStart < 0 || loopStart % 16 || loopStart >= pcm.length)) throw new Error('Invalid loop start');
  const bytes = new Uint8Array(pcm.length / 16 * 9);
  let a = 0, b = 0;
  for (let pos = 0; pos < pcm.length; pos += 16) {
    let best;
    for (let filter = 0; filter < (pos === 0 || pos === loopStart ? 1 : 4); filter++) {
      for (let range = 0; range <= 12; range++) {
        let x = a, y = b, error = 0;
        const ns = [];
        for (let i = 0; i < 16; i++) {
          let chosen = 0, decoded = 0, distance = Infinity;
          for (let n = -8; n <= 7; n++) {
            const v = sample(n, range, filter, x, y), d = pcm[pos + i] - v * 2;
            if (d * d < distance) { distance = d * d; chosen = n; decoded = v; }
          }
          error += distance; ns.push(chosen & 15); y = x; x = decoded;
        }
        if (!best || error < best.error) best = { error, ns, range, filter, a: x, b: y };
      }
    }
    const at = pos / 16 * 9;
    bytes[at] = best.range << 4 | best.filter << 2;
    for (let i = 0; i < 8; i++) bytes[at + 1 + i] = best.ns[2 * i] << 4 | best.ns[2 * i + 1];
    a = best.a; b = best.b;
  }
  bytes[bytes.length - 9] |= loopStart === null ? 1 : 3;
  return bytes;
}
