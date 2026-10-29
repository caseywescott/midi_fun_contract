// Canonical normalized musical-input wire format shared with beast_composer_inputs.
// This module has no token decoder, chain access, player or entropy source.
export const COMPOSER_INPUTS_VERSION = 4;
export const GENERATION_INPUTS_VERSION = 2;
export const MAX_TEMPO_US = 1048575;
export const FIELD_P = (1n << 251n) + 17n * (1n << 192n) + 1n;
const U64_MAX = (1n << 64n) - 1n;
const ownKeys = (x, names) => {
  if (!x || typeof x !== 'object' || Array.isArray(x)
      || Object.keys(x).length !== names.length || names.some((k) => !Object.hasOwn(x, k))) {
    throw new Error('invalid musical fields');
  }
};
function integer(x, max = FIELD_P - 1n) {
  if (typeof x === 'number' && !Number.isSafeInteger(x)) throw new Error('unsafe musical integer');
  if (typeof x !== 'number' && typeof x !== 'bigint') throw new Error('invalid musical integer');
  const n = BigInt(x);
  if (n < 0n || n > max) throw new Error('musical integer out of range');
  return n;
}
const small = (x, max) => Number(integer(x, BigInt(max)));
const bool = (x) => { if (typeof x !== 'boolean') throw new Error('invalid musical boolean'); return x; };
const fields = {
  identity: [['source_species_id', 'u64'], ['name_variant_id', 'u16']],
  theme: [['motif_seed', 'felt'], ['tier', 'u8'], ['register_band', 'u8']],
  score: [['mode_id', 'u8'], ['tonic_keynum', 'u8'], ['tier', 'u8'], ['weakness', 'u8'],
    ['voice_count', 'u8'], ['section_count', 'u8'], ['stretto_lag', 'u8'],
    ['use_inversion', 'bool'], ['use_countersubject', 'bool'], ['ornament_density', 'u8'],
    ['articulation_profile', 'u8'], ['velocity_ceiling', 'u8'], ['tempo_us', 'u32']],
  treatment: [['rhythm_seed', 'felt'], ['flip_side', 'bool'], ['development', 'u8'],
    ['direction', 'u8'], ['spacing', 'u8'], ['trill', 'bool'], ['prominence', 'u8'], ['section_rhythm', 'bool']],
  arrangement: [['family', 'u8'], ['identity', 'identity'], ['channel_count', 'u8'],
    ['channel_policy', 'policy'], ['special', 'special'], ['top_lead', 'bool'],
    ['balanced', 'bool'], ['weak_ties', 'bool']],
  song: [['theme', 'theme'], ['score', 'score'], ['treatment', 'treatment'], ['arrangement', 'arrangement']],
  check: [['identity', 'identity'], ['mode_id', 'u8'], ['tonic_keynum', 'u8'], ['family', 'u8'],
    ['tempo_us', 'u32'], ['velocity_ceiling', 'u8'], ['articulation_profile', 'u8']],
};
const limits = { u8: 255n, u16: 65535n, u32: 4294967295n, u64: U64_MAX, felt: FIELD_P - 1n };
function write(type, value, out) {
  if (fields[type]) {
    ownKeys(value, fields[type].map(([name]) => name));
    for (const [name, child] of fields[type]) write(child, value[name], out);
  } else if (type === 'bool') out.push(bool(value) ? 1n : 0n);
  else if (type === 'policy') {
    if (value?.kind === 'Genesis') { ownKeys(value, ['kind']); out.push(0n); }
    else if (value?.kind === 'Seeded') { ownKeys(value, ['kind', 'seed']); out.push(1n, integer(value.seed)); }
    else throw new Error('unknown channel policy');
  } else if (type === 'special') {
    if (value?.kind === 'None') { ownKeys(value, ['kind']); out.push(0n); }
    else if (value?.kind === 'Yeti') {
      ownKeys(value, ['kind', 'name_variant_id']); out.push(1n, integer(value.name_variant_id, 65535n));
    } else throw new Error('unknown special arrangement');
  } else out.push(integer(value, limits[type]));
}
function reader(values) {
  if (!Array.isArray(values)) throw new Error('invalid musical wire');
  let pos = 0;
  const take = () => { if (pos === values.length) throw new Error('truncated musical wire'); return integer(values[pos++]); };
  function read(type) {
    if (fields[type]) return Object.fromEntries(fields[type].map(([name, child]) => [name, read(child)]));
    const value = take();
    if (type === 'bool') { if (value > 1n) throw new Error('invalid musical boolean'); return value === 1n; }
    if (type === 'policy') {
      if (value === 0n) return { kind: 'Genesis' };
      if (value === 1n) return { kind: 'Seeded', seed: take() };
      throw new Error('unknown channel policy');
    }
    if (type === 'special') {
      if (value === 0n) return { kind: 'None' };
      if (value === 1n) return { kind: 'Yeti', name_variant_id: small(take(), 65535) };
      throw new Error('unknown special arrangement');
    }
    if (value > limits[type]) throw new Error('musical integer out of range');
    return type === 'felt' || type === 'u64' ? value : Number(value);
  }
  return { take, read, end: () => { if (pos !== values.length) throw new Error('extra musical wire data'); } };
}
const requireThat = (ok, message) => { if (!ok) throw new Error(message); };
function identity(x) {
  requireThat(integer(x.source_species_id, U64_MAX) > 0n, 'invalid music identity');
  requireThat(small(x.name_variant_id, 65535) <= 1242, 'invalid music name');
}
function expression(x) {
  requireThat(x.tempo_us >= 1 && x.tempo_us <= MAX_TEMPO_US, 'invalid musical tempo');
  requireThat(x.velocity_ceiling >= 1 && x.velocity_ceiling <= 127, 'invalid musical velocity');
  requireThat([0, 1, 2, 3, 5].includes(x.articulation_profile), 'invalid articulation');
}
function mode(x) { requireThat([4, 5, 6, 7, 8, 26].includes(x), 'unsupported musical mode'); }
function tier(x) { requireThat(x >= 1 && x <= 5, 'invalid musical tier'); }
function validateSong(x) {
  const p = x.score;
  identity(x.arrangement.identity); mode(p.mode_id); tier(p.tier); tier(x.theme.tier); expression(p);
  requireThat(x.theme.register_band <= 2, 'invalid theme register');
  requireThat(p.tonic_keynum >= 24 && p.tonic_keynum <= 96, 'invalid song tonic');
  requireThat(p.weakness <= 2, 'invalid rhythm family');
  requireThat(p.voice_count >= 1 && p.voice_count <= 4, 'invalid voice count');
  requireThat(p.section_count >= 1 && p.section_count <= 5, 'invalid section count');
  requireThat(p.stretto_lag >= 1 && p.stretto_lag <= 4, 'invalid entry lag');
  requireThat(p.ornament_density <= 7, 'invalid ornament density');
  requireThat(x.treatment.development <= 2, 'invalid development');
  requireThat(x.treatment.direction <= 2, 'invalid episode direction');
  requireThat(x.treatment.spacing <= 2, 'invalid voice spacing');
  requireThat(x.treatment.prominence <= 3, 'invalid prominence');
  requireThat(x.arrangement.family <= 2, 'invalid program family');
  const roles = p.voice_count + Number(p.use_countersubject) + 1;
  requireThat(x.arrangement.channel_count >= 1 && x.arrangement.channel_count <= roles, 'invalid channel count');
  if (x.arrangement.special.kind === 'Yeti') requireThat(x.arrangement.special.name_variant_id <= 1242, 'invalid ornament name');
}
function validateCheck(x) {
  identity(x.identity); mode(x.mode_id); expression(x);
  requireThat(x.tonic_keynum <= 103, 'invalid sound check tonic');
  requireThat(x.family <= 2, 'invalid program family');
}
export function encodeInputs(x) {
  const out = [BigInt(COMPOSER_INPUTS_VERSION)];
  if (x?.kind === 'Song') {
    ownKeys(x, ['kind', 'song']); out.push(1n); write('song', x.song, out); validateSong(x.song);
  } else if (x?.kind === 'SoundCheck') {
    ownKeys(x, ['kind', 'check']); out.push(0n); write('check', x.check, out); validateCheck(x.check);
  } else throw new Error('unknown recipe kind');
  return out;
}
export function decodeInputs(values) {
  const r = reader(values);
  requireThat(r.take() === BigInt(COMPOSER_INPUTS_VERSION), 'unknown inputs version');
  const kind = r.take();
  const x = kind === 0n ? { kind: 'SoundCheck', check: r.read('check') }
    : kind === 1n ? { kind: 'Song', song: r.read('song') } : null;
  requireThat(x !== null, 'unknown recipe kind'); r.end(); encodeInputs(x); return x;
}
export function encodeGenerationInputs(x) {
  ownKeys(x, ['base_song']);
  const out = [BigInt(GENERATION_INPUTS_VERSION)];
  write('song', x.base_song, out); validateSong(x.base_song); return out;
}
export function decodeGenerationInputs(values) {
  const r = reader(values);
  requireThat(r.take() === BigInt(GENERATION_INPUTS_VERSION), 'unknown generation version');
  const x = { base_song: r.read('song') }; r.end(); encodeGenerationInputs(x); return x;
}
export function applyPerformance(inputs, code) {
  encodeInputs(inputs);
  requireThat(Number.isInteger(code) && code >= 0 && code <= 3, 'invalid sound effects');
  // Copies also canonicalize u64/felt values without ever mutating the authored recipe.
  const result = decodeInputs(encodeInputs(inputs));
  if (code === 0) return result;
  const [bump, lift, profile] = [[0, 0, 0], [25000, 12, 2], [30000, 8, 5], [45000, 15, 3]][code];
  const p = result.kind === 'Song' ? result.song.score : result.check;
  p.tempo_us = Math.max(1, p.tempo_us - bump);
  p.velocity_ceiling = Math.min(127, p.velocity_ceiling + lift);
  p.articulation_profile = profile;
  return result;
}
