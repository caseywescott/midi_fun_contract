// Starknet Poseidon (poseidon_hash_many) in ~1 KB minified, for bundles where @scure/starknet's
// curve and hash helpers would dominate (the onchain token_uri composer).
//
// Same permutation as @scure/starknet's poseidonSmall: width 3, x^3 S-box, 4 + 83 + 4 rounds, MDS
// [[3,1,1],[1,-1,1],[1,1,-2]], partial-round S-box on the last lane. Round constant i is
// sha256("Hades" + i) mod p, computed on first use, so nothing is hardcoded. Tested against
// @scure/starknet in test/poseidon_lite.test.mjs.

const P = 2n ** 251n + 17n * 2n ** 192n + 1n;

// SHA-256 of a short ASCII string (one or two blocks) as a BigInt.
function sha256(str) {
  const K = [];
  const frac = (x) => ((x - Math.floor(x)) * 2 ** 32) >>> 0;
  for (let n = 2; K.length < 64; n++) {
    let prime = true;
    for (let d = 2; d * d <= n; d++) if (n % d === 0) { prime = false; break; }
    if (prime) K.push(frac(Math.cbrt(n)));
  }
  const H = [2, 3, 5, 7, 11, 13, 17, 19].map((n) => frac(Math.sqrt(n)));
  const bytes = [...str].map((c) => c.charCodeAt(0));
  const bits = bytes.length * 8;
  bytes.push(0x80);
  while (bytes.length % 64 !== 56) bytes.push(0);
  for (let i = 7; i >= 0; i--) bytes.push(i > 3 ? 0 : (bits >>> (i * 8)) & 255);
  const rotr = (x, n) => (x >>> n) | (x << (32 - n));
  for (let o = 0; o < bytes.length; o += 64) {
    const w = [];
    for (let i = 0; i < 64; i++) {
      if (i < 16) w[i] = (bytes[o + 4 * i] << 24) | (bytes[o + 4 * i + 1] << 16) | (bytes[o + 4 * i + 2] << 8) | bytes[o + 4 * i + 3];
      else {
        const a = w[i - 15], b = w[i - 2];
        w[i] = (w[i - 16] + (rotr(a, 7) ^ rotr(a, 18) ^ (a >>> 3)) + w[i - 7] + (rotr(b, 17) ^ rotr(b, 19) ^ (b >>> 10))) | 0;
      }
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const t1 = (h + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i]) | 0;
      const t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
      h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
    }
    [a, b, c, d, e, f, g, h].forEach((v, i) => { H[i] = (H[i] + v) | 0; });
  }
  return H.reduce((acc, v) => (acc << 32n) | BigInt(v >>> 0), 0n);
}

let RC = null;
const roundConstants = () => RC || (RC = Array.from({ length: 91 * 3 }, (_, i) => sha256('Hades' + i) % P));

function permute(s) {
  const rc = roundConstants();
  let [x, y, z] = s;
  for (let r = 0; r < 91; r++) {
    x = (x + rc[3 * r]) % P; y = (y + rc[3 * r + 1]) % P; z = (z + rc[3 * r + 2]) % P;
    const full = r < 4 || r >= 87;
    if (full) { x = x ** 3n % P; y = y ** 3n % P; }
    z = z ** 3n % P;
    const sum = x + y + z;
    [x, y, z] = [(sum + 2n * x) % P, (sum - 2n * y + P * 2n) % P, (sum - 3n * z + P * 3n) % P];
  }
  return [x, y, z];
}

/** poseidon_hash_many: absorb in pairs after appending 1 (and 0 to even out), return lane 0. */
export function poseidonHashMany(values) {
  const v = values.map((x) => ((BigInt(x) % P) + P) % P);
  v.push(1n);
  if (v.length % 2) v.push(0n);
  let s = [0n, 0n, 0n];
  for (let i = 0; i < v.length; i += 2) s = permute([(s[0] + v[i]) % P, (s[1] + v[i + 1]) % P, s[2]]);
  return s[0];
}
