//! Beasts V3 adapter for Beast Sound.
//!
//! Beasts V3 (Provable-Games/beasts `docs/community-beasts-design.md`) encodes every static
//! Beast trait in a deterministic 116-bit token ID:
//!
//!   id u64 | prefix 7b | suffix 5b | level 16b | health 16b | shiny 1b | animated 1b
//!   | tier 3b | type 3b
//!
//! Genesis tokens are `(id, 0, 0)`; dungeon mints have `prefix >= 1 && suffix >= 1`, so every
//! species has exactly 1,243 tokens (75 x 1,243 = 93,225 for the original collection).
//!
//! This module maps a decoded V3 Beast plus its live dungeon state into the existing
//! `BeastCompositionParams`, so the established `build_beast_form` renderer is reused unchanged.
//! Everything here is a pure function of (token ID, live state): no storage, no external calls.
//!
//! Differences from the legacy `map_beast_traits_to_composition_params` mapper:
//! - species ids are the real Loot Survivor ids (1..75 genesis, 76+ community), not 0..74;
//! - tier and type come from the token ID (authoritative), not a formula over species id;
//! - prefix/suffix are used directly (1..69 / 1..18), genesis (0, 0) is the bare-name Beast;
//! - shiny and animated are two independent flags, not a four-value enum;
//! - level and health (fixed at mint) now shape voice count and register;
//! - rank is read relative to the species population, since species sizes differ;
//! - the sound seed is derived from the entity hash inputs only, so it survives the V2 -> V3
//!   `burn_and_mint` migration (no chain id or contract address in the identity);
//! - "scars" come from Summit deaths (`revival_count`), the one defeat counter that moves:
//!   every minted Beast has a Death Mountain collect count of exactly 1;
//! - time held on the Summit adds to the Beast's history and, past 16 hours, to its ornament.
//!
//! Authority for per-species sound settings follows Beasts V3: the species' creator is whoever
//! holds its Genesis Beast `(id, 0, 0)` (see `genesis_token_id`).

use core::poseidon::poseidon_hash_span;
use koji::composition::beast_score::{BeastForm, build_beast_form, beast_params_hash};
use koji::composition::beast_trait_map::{
    ARTICULATION_ACCENT, ARTICULATION_NORMAL, ARTICULATION_PORTATO, ARTICULATION_TENUTO,
    BeastCompositionParams, BeastKeyCell, BeastOrnamentPolicy, REGISTER_HIGH, REGISTER_LOW,
    REGISTER_MID, WEAKNESS_BLADE, WEAKNESS_BLUDGEON, WEAKNESS_MAGIC, bucket_log2, clamp_u8,
    prefix1_to_beast_key, prefix2_ornament_policy, sections_for_kill_bucket,
    tonic_keynum_for_cell,
};
use koji::composition::counterpoint::mode_to_id;
use koji::composition::stretto::{default_stretto_plan, stretto_lag};
use koji::midi::types::Modes;

pub const BEAST_V3_ENGINE_VERSION: u32 = 1;

pub const BEAST_TYPE_MAGIC: u8 = 0;
pub const BEAST_TYPE_HUNTER: u8 = 1;
pub const BEAST_TYPE_BRUTE: u8 = 2;

/// Genesis species ids are 1..=75; community species start at 76.
pub const GENESIS_SPECIES_MAX: u64 = 75;
/// Health at or above this sits one register band lower ("heavier" Beasts).
pub const HEAVY_HEALTH: u16 = 250;
/// Level at or above this unlocks one extra voice below the tier ceiling.
pub const VETERAN_LEVEL: u16 = 64;
/// Default Sound drop rate for dungeon-minted Beasts, in basis points (5%).
pub const SOUND_DROP_BPS_DEFAULT: u32 = 500;
/// Summit bucket (log2 of hours held) at which the Summit layer adds ornament density.
pub const SUMMIT_GLORY_BUCKET: u8 = 4;
/// Provenance attributes every Genesis Beast is minted with (`mint_provenance`).
pub const GENESIS_LEVEL: u16 = 1;
pub const GENESIS_HEALTH: u16 = 100;

const TWO_POW_64: u256 = 0x10000000000000000;
const TWO_POW_7: u256 = 0x80;
const TWO_POW_5: u256 = 0x20;
const TWO_POW_16: u256 = 0x10000;

/// Mirror of Beasts V3 `pack::PackableBeast`.
#[derive(Copy, Drop, Serde, PartialEq)]
pub struct PackableBeastV3 {
    pub id: u64,
    pub prefix: u8,
    pub suffix: u8,
    pub level: u16,
    pub health: u16,
    pub shiny: u8,
    pub animated: u8,
    pub tier: u8,
    pub beast_type: u8,
}

/// Live state read from contracts that already exist; nothing here is stored by Sound.
#[derive(Copy, Drop, Serde)]
pub struct BeastV3LiveState {
    /// Beasts NFT `get_adventurers_killed(token_id)`: live Death Mountain read for species
    /// 1-75, the `refresh_stats` cache for community species.
    pub adventurers_killed: u64,
    /// Defeats after mint: Summit `LiveBeastStats.revival_count` plus Death Mountain
    /// `get_collectable_count - 1` (the mint itself is one collect).
    pub scars: u64,
    /// Summit `LiveBeastStats.summit_held_seconds`.
    pub summit_held_seconds: u64,
    /// `get_beast_rank(token_id)`; 0 for the genesis token (unranked).
    pub rank: u16,
    /// `get_species_count(beast_id)`.
    pub species_count: u16,
}

/// Normalized music state: the only live inputs the composer sees.
#[derive(Copy, Drop, Serde)]
pub struct BeastV3MusicState {
    pub kill_bucket: u8,
    pub defeat_bucket: u8,
    pub summit_bucket: u8,
    pub encounter_bucket: u8,
    pub rank_tier: u8,
    pub is_crown: bool,
}

#[derive(Copy, Drop, Serde)]
pub struct BeastTypeTierFamily {
    pub canon_config_id: u32,
    pub profile_id: u32,
    pub base_voice_count: u32,
}

/// Decode a Beasts V3 token ID (same layout and validation as `pack::decode_token_id`).
pub fn decode_v3_token_id(token_id: u256) -> PackableBeastV3 {
    let mut packed = token_id;
    let id: u64 = (packed % TWO_POW_64).try_into().unwrap();
    packed = packed / TWO_POW_64;
    let prefix: u8 = (packed % TWO_POW_7).try_into().unwrap();
    packed = packed / TWO_POW_7;
    let suffix: u8 = (packed % TWO_POW_5).try_into().unwrap();
    packed = packed / TWO_POW_5;
    let level: u16 = (packed % TWO_POW_16).try_into().unwrap();
    packed = packed / TWO_POW_16;
    let health: u16 = (packed % TWO_POW_16).try_into().unwrap();
    packed = packed / TWO_POW_16;
    let shiny: u8 = (packed % 2).try_into().unwrap();
    packed = packed / 2;
    let animated: u8 = (packed % 2).try_into().unwrap();
    packed = packed / 2;
    let tier: u8 = (packed % 8).try_into().unwrap();
    packed = packed / 8;
    let beast_type: u8 = (packed % 8).try_into().unwrap();
    packed = packed / 8;
    assert(packed == 0, 'invalid token id');
    let beast = PackableBeastV3 {
        id, prefix, suffix, level, health, shiny, animated, tier, beast_type,
    };
    assert_valid_v3_beast(beast);
    beast
}

pub fn encode_v3_token_id(beast: PackableBeastV3) -> u256 {
    beast.id.into()
        + beast.prefix.into() * TWO_POW_64
        + beast.suffix.into() * 0x800000000000000000
        + beast.level.into() * 0x10000000000000000000
        + beast.health.into() * 0x100000000000000000000000
        + beast.shiny.into() * 0x1000000000000000000000000000
        + beast.animated.into() * 0x2000000000000000000000000000
        + beast.tier.into() * 0x4000000000000000000000000000
        + beast.beast_type.into() * 0x20000000000000000000000000000
}

pub fn assert_valid_v3_beast(beast: PackableBeastV3) {
    assert(beast.id != 0, 'invalid beast id');
    assert(beast.tier >= 1 && beast.tier <= 5, 'invalid tier');
    assert(beast.beast_type <= 2, 'invalid type');
    assert(beast.prefix <= 69, 'invalid prefix');
    assert(beast.suffix <= 18, 'invalid suffix');
    assert((beast.prefix == 0) == (beast.suffix == 0), 'invalid affix combo');
    assert(beast.shiny <= 1 && beast.animated <= 1, 'invalid visual flag');
}

pub fn is_genesis(beast: PackableBeastV3) -> bool {
    beast.prefix == 0
}

/// Legacy name-variant index: 0 = bare/genesis, else 1 + (prefix-1)*18 + (suffix-1).
/// Keeps parity with the vault encoding (`decode_name_variant`).
pub fn v3_name_variant_id(prefix: u8, suffix: u8) -> u32 {
    if prefix == 0 {
        0
    } else {
        let p: u32 = (prefix - 1).into();
        let s: u32 = (suffix - 1).into();
        1 + p * 18 + s
    }
}

/// Token ID of a species' Genesis Beast `(id, 0, 0)`. In Beasts V3 its holder is the species'
/// artist, so this is the authority for per-species sound settings.
pub fn genesis_token_id(id: u64, tier: u8, beast_type: u8) -> u256 {
    encode_v3_token_id(
        PackableBeastV3 {
            id, prefix: 0, suffix: 0, level: GENESIS_LEVEL, health: GENESIS_HEALTH, shiny: 1,
            animated: 1, tier, beast_type,
        },
    )
}

/// Immutable sound identity. Same inputs as the Beasts entity hash `poseidon(id, prefix, suffix)`
/// with a domain tag, so it is stable across the V3 migration and independent of owner, chain,
/// and contract address.
pub fn beast_sound_seed(id: u64, prefix: u8, suffix: u8) -> felt252 {
    poseidon_hash_span(array!['BEAST_SOUND_V1', id.into(), prefix.into(), suffix.into()].span())
}

/// Seed for a Beast in a standalone collection (Tiddy Mun, Black Shuck, ...) that reuses
/// species ids from 1. The collection address keeps it from colliding with V3 Beasts.
pub fn standalone_sound_seed(collection: felt252, id: u64, prefix: u8, suffix: u8) -> felt252 {
    poseidon_hash_span(
        array!['BEAST_SOUND_V1', collection, id.into(), prefix.into(), suffix.into()].span(),
    )
}

/// Deterministic Sound rarity roll in [0, 10000). `salt` should be committed before the drop
/// and revealed at launch (e.g. a future block hash) so nobody can pre-compute winners.
pub fn sound_drop_roll(salt: felt252, id: u64, prefix: u8, suffix: u8) -> u32 {
    let h = poseidon_hash_span(
        array!['BEAST_SOUND_DROP', salt, id.into(), prefix.into(), suffix.into()].span(),
    );
    let hu: u256 = h.into();
    (hu % 10000).try_into().unwrap()
}

/// Genesis (Creator) Beasts always carry Sound; dungeon Beasts carry it when the roll lands
/// under `drop_bps`.
pub fn beast_has_sound(salt: felt252, drop_bps: u32, beast: PackableBeastV3) -> bool {
    if is_genesis(beast) {
        return true;
    }
    sound_drop_roll(salt, beast.id, beast.prefix, beast.suffix) < drop_bps
}

/// Canon family per (type, tier). Works for any species, including community Beasts, which
/// only declare a type and tier at registration.
pub fn type_tier_family(beast_type: u8, tier: u8) -> BeastTypeTierFamily {
    assert(beast_type <= 2, 'invalid type');
    assert(tier >= 1 && tier <= 5, 'invalid tier');
    let base_voice_count: u32 = if tier <= 2 {
        3
    } else if tier == 3 {
        2
    } else {
        1
    };
    let (canon_config_id, profile_id): (u32, u32) = if beast_type == BEAST_TYPE_MAGIC {
        if tier == 1 {
            (18, 8) // dom_alt_b9: occult fire
        } else if tier == 2 {
            (25, 15) // cluster_soft
        } else if tier == 3 {
            (34, 19) // phrygian 3v
        } else if tier == 4 {
            (40, 0) // penta_smooth 3v
        } else {
            (3, 0) // unison
        }
    } else if beast_type == BEAST_TYPE_HUNTER {
        if tier == 1 {
            (24, 14) // bartok_axis: aerial hunt
        } else if tier == 2 {
            (29, 19) // phrygian 4v
        } else if tier == 3 {
            (30, 0) // penta_open 4v
        } else {
            (1, 0) // fifth_below
        }
    } else if tier == 1 {
        (20, 10) // oct_axis: storm / abyss
    } else if tier == 2 {
        (11, 2) // quartal4_stack
    } else if tier == 3 {
        (12, 4) // hindemith4
    } else if tier == 4 {
        (10, 2) // quartal_stack
    } else {
        (4, 0) // three_5b_8va
    };
    BeastTypeTierFamily { canon_config_id, profile_id, base_voice_count }
}

/// Section B key relation by Beast type (Magic: tritone, Hunter: up a 5th, Brute: down a 4th).
/// Expressed through the existing weakness codes so `section_tonic_shift` is reused unchanged.
pub fn type_to_section_relation(beast_type: u8) -> u8 {
    if beast_type == BEAST_TYPE_MAGIC {
        WEAKNESS_MAGIC
    } else if beast_type == BEAST_TYPE_HUNTER {
        WEAKNESS_BLADE
    } else {
        WEAKNESS_BLUDGEON
    }
}

/// Shiny and Animated are independent flags; Animated + Shiny stacks both layers.
/// Returns (tempo_bump_us, velocity_ceiling, articulation_profile).
pub fn v3_visual_layer(shiny: u8, animated: u8) -> (u32, u8, u8) {
    if shiny == 1 && animated == 1 {
        (45000, 127, ARTICULATION_ACCENT)
    } else if animated == 1 {
        (30000, 120, ARTICULATION_PORTATO)
    } else if shiny == 1 {
        (25000, 124, ARTICULATION_TENUTO)
    } else {
        (0, 112, ARTICULATION_NORMAL)
    }
}

/// Rank tier relative to the species population: 0 crown, 1 top 1% (or genesis), 2 top 5%,
/// 3 top 20%, 4 the rest.
pub fn v3_rank_tier(rank: u16, species_count: u16) -> u8 {
    if rank == 0 {
        return 1;
    }
    if rank == 1 {
        return 0;
    }
    let count: u32 = if species_count == 0 {
        1
    } else {
        species_count.into()
    };
    let permille: u32 = rank.into() * 1000 / count;
    if permille <= 10 {
        1
    } else if permille <= 50 {
        2
    } else if permille <= 200 {
        3
    } else {
        4
    }
}

fn clamp_u64_to_u32(v: u64) -> u32 {
    if v > 0xffffffff {
        0xffffffff
    } else {
        v.try_into().unwrap()
    }
}

fn saturating_add(a: u32, b: u32) -> u32 {
    if a > 0xffffffff - b {
        0xffffffff
    } else {
        a + b
    }
}

pub fn v3_music_state(live: BeastV3LiveState) -> BeastV3MusicState {
    let kills = clamp_u64_to_u32(live.adventurers_killed);
    let scars = clamp_u64_to_u32(live.scars);
    let summit_hours = clamp_u64_to_u32(live.summit_held_seconds / 3600);
    BeastV3MusicState {
        kill_bucket: bucket_log2(kills),
        defeat_bucket: bucket_log2(scars),
        summit_bucket: bucket_log2(summit_hours),
        encounter_bucket: bucket_log2(saturating_add(saturating_add(kills, scars), summit_hours)),
        rank_tier: v3_rank_tier(live.rank, live.species_count),
        is_crown: live.rank == 1,
    }
}

fn genesis_key(id: u64, tier: u8) -> BeastKeyCell {
    let mode = Modes::Phrygian(());
    let register_band = if tier <= 2 {
        REGISTER_LOW
    } else if tier <= 4 {
        REGISTER_MID
    } else {
        REGISTER_HIGH
    };
    BeastKeyCell {
        canonical_mode_id: mode_to_id(mode),
        mode,
        tonic_pc: (id % 12).try_into().unwrap(),
        register_band,
    }
}

pub fn map_v3_beast_to_composition_params(
    beast: PackableBeastV3, live: BeastV3LiveState,
) -> BeastCompositionParams {
    assert_valid_v3_beast(beast);
    let tier = beast.tier;
    let family = type_tier_family(beast.beast_type, tier);
    let genesis = is_genesis(beast);
    let mut key = if genesis {
        genesis_key(beast.id, tier)
    } else {
        prefix1_to_beast_key(beast.prefix - 1, tier)
    };
    if beast.health >= HEAVY_HEALTH && key.register_band > REGISTER_LOW {
        key.register_band -= 1;
    }
    let ornament = if genesis {
        BeastOrnamentPolicy {
            profile_id: family.profile_id,
            density_cap: 1,
            allow_chromatic_approach: false,
            allow_suspension: tier <= 3,
            allow_trill: false,
        }
    } else {
        prefix2_ornament_policy(beast.suffix - 1)
    };
    let (tempo_bump, velocity_ceiling, visual_articulation) = v3_visual_layer(
        beast.shiny, beast.animated,
    );
    let state = v3_music_state(live);
    let crown_bump: u8 = if state.is_crown && state.kill_bucket < 7 {
        1
    } else {
        0
    };
    let stretto_bucket = state.kill_bucket + crown_bump;
    let extra_voice: u32 = if state.kill_bucket >= 4 && tier <= 3 {
        1
    } else {
        0
    };
    let rank_voice: u32 = if state.rank_tier <= 1 && tier <= 2 {
        1
    } else {
        0
    };
    let level_voice: u32 = if beast.level >= VETERAN_LEVEL && tier <= 4 {
        1
    } else {
        0
    };
    let max_voice: u32 = if tier <= 2 {
        4
    } else if tier == 3 {
        3
    } else {
        2
    };
    let raw_voice = family.base_voice_count + extra_voice + rank_voice + level_voice;
    let voice_count = if raw_voice > max_voice {
        max_voice
    } else {
        raw_voice
    };
    let density_raw: u32 = ornament.density_cap.into()
        + state.kill_bucket.into()
        + if state.is_crown {
            1
        } else {
            0
        }
        + if state.summit_bucket >= SUMMIT_GLORY_BUCKET {
            1
        } else {
            0
        };
    BeastCompositionParams {
        species_id: beast.id,
        name_variant_id: v3_name_variant_id(beast.prefix, beast.suffix),
        mode_id: key.canonical_mode_id,
        tonic_keynum: tonic_keynum_for_cell(key),
        register_band: key.register_band,
        tier,
        weakness: type_to_section_relation(beast.beast_type),
        canon_config_id: family.canon_config_id,
        profile_id: family.profile_id,
        voice_count,
        section_count: sections_for_kill_bucket(state.kill_bucket),
        stretto_bucket,
        stretto_lag: stretto_lag(@default_stretto_plan(), stretto_bucket),
        use_inversion: state.defeat_bucket >= 3 || (tier <= 2 && state.encounter_bucket >= 4),
        use_countersubject: tier <= 2 || (tier == 3 && state.rank_tier <= 1),
        use_compound_melody: tier >= 4,
        ornament_density: clamp_u8(density_raw, 7),
        articulation_profile: if state.is_crown {
            ARTICULATION_ACCENT
        } else {
            visual_articulation
        },
        velocity_ceiling,
        tempo_us: 500000 - tempo_bump,
        score_version: BEAST_V3_ENGINE_VERSION,
    }
}

/// Cache key for renderers: changes only when a normalized bucket, rank tier, or the engine
/// version changes, never on every raw counter tick.
pub fn v3_music_state_hash(beast: PackableBeastV3, live: BeastV3LiveState) -> felt252 {
    let state = v3_music_state(live);
    let crown: felt252 = if state.is_crown {
        1
    } else {
        0
    };
    poseidon_hash_span(
        array![
            'BEAST_MUSIC_STATE_V3', beast_sound_seed(beast.id, beast.prefix, beast.suffix),
            BEAST_V3_ENGINE_VERSION.into(), beast.level.into(), beast.health.into(),
            beast.shiny.into(), beast.animated.into(), beast.tier.into(), beast.beast_type.into(),
            state.kill_bucket.into(), state.defeat_bucket.into(), state.summit_bucket.into(),
            state.encounter_bucket.into(), state.rank_tier.into(), crown,
        ]
            .span(),
    )
}

pub fn build_v3_beast_form(beast: PackableBeastV3, live: BeastV3LiveState) -> BeastForm {
    let params = map_v3_beast_to_composition_params(beast, live);
    build_beast_form(params, beast_sound_seed(beast.id, beast.prefix, beast.suffix))
}

pub fn v3_params_hash(beast: PackableBeastV3, live: BeastV3LiveState) -> felt252 {
    beast_params_hash(map_v3_beast_to_composition_params(beast, live))
}

// ─────────────────────────────────────────────────────────────
// Standard MIDI File encoding (format 1, 480 PPQN, one track per voice)
// ─────────────────────────────────────────────────────────────
//
// One form tick is one quarter note at 480 PPQN, so event times are written as-is. Each voice's
// events are emitted in time order by `build_beast_form` (and a note ends before the voice's next
// note starts), so tracks need no sorting: the encoder walks the event list once per voice.
// Byte-identical to `toMidiFile` in web/beast_sound/engine.js.

fn push_u32_be(ref out: Array<u8>, v: u32) {
    out.append(((v / 0x1000000) % 256).try_into().unwrap());
    out.append(((v / 0x10000) % 256).try_into().unwrap());
    out.append(((v / 0x100) % 256).try_into().unwrap());
    out.append((v % 256).try_into().unwrap());
}

fn push_vlq(ref out: Array<u8>, v: u32) {
    // Up to 4 bytes covers every delta below 2^28 ticks.
    if v >= 0x200000 {
        out.append((0x80 + (v / 0x200000) % 128).try_into().unwrap());
    }
    if v >= 0x4000 {
        out.append((0x80 + (v / 0x4000) % 128).try_into().unwrap());
    }
    if v >= 0x80 {
        out.append((0x80 + (v / 0x80) % 128).try_into().unwrap());
    }
    out.append((v % 128).try_into().unwrap());
}

fn push_chunk(ref out: Array<u8>, tag: u32, body: Span<u8>) {
    push_u32_be(ref out, tag);
    push_u32_be(ref out, body.len());
    let mut i: u32 = 0;
    while i < body.len() {
        out.append(*body.at(i));
        i += 1;
    }
}

const TAG_MTHD: u32 = 0x4D546864;
const TAG_MTRK: u32 = 0x4D54726B;

pub fn beast_form_to_smf_bytes(form: @BeastForm, tempo_us: u32) -> Array<u8> {
    let events = form.events.span();
    let mut max_voice: u32 = 0;
    let mut i: u32 = 0;
    while i < events.len() {
        let v = *events.at(i).voice_id;
        if v > max_voice {
            max_voice = v;
        }
        i += 1;
    }

    let mut tracks: Array<Array<u8>> = array![];
    let mut tempo_track: Array<u8> = array![0, 0xFF, 0x51, 0x03];
    tempo_track.append(((tempo_us / 0x10000) % 256).try_into().unwrap());
    tempo_track.append(((tempo_us / 0x100) % 256).try_into().unwrap());
    tempo_track.append((tempo_us % 256).try_into().unwrap());
    // End of Track at the form's full length (closing rest included), so the file is as long as the form
    push_vlq(ref tempo_track, *form.length_ticks);
    tempo_track.append(0xFF);
    tempo_track.append(0x2F);
    tempo_track.append(0);
    tracks.append(tempo_track);

    let mut v: u32 = 0;
    while v <= max_voice {
        let mut track: Array<u8> = array![];
        let mut t: u32 = 0;
        let mut any = false;
        let status_on: u8 = (0x90 + v % 16).try_into().unwrap();
        let status_off: u8 = (0x80 + v % 16).try_into().unwrap();
        let mut j: u32 = 0;
        while j < events.len() {
            let e = *events.at(j);
            if e.voice_id == v {
                any = true;
                push_vlq(ref track, e.time - t);
                track.append(status_on);
                track.append(e.pitch);
                track.append(e.velocity);
                let off = e.time + e.duration;
                push_vlq(ref track, off - e.time);
                track.append(status_off);
                track.append(e.pitch);
                track.append(64);
                t = off;
            }
            j += 1;
        }
        if any {
            track.append(0);
            track.append(0xFF);
            track.append(0x2F);
            track.append(0);
            tracks.append(track);
        }
        v += 1;
    }

    let mut out: Array<u8> = array![];
    let n: u32 = tracks.len();
    let header: Array<u8> = array![
        0, 1, ((n / 256) % 256).try_into().unwrap(), (n % 256).try_into().unwrap(), 0x01, 0xE0,
    ];
    push_chunk(ref out, TAG_MTHD, header.span());
    let mut k: u32 = 0;
    while k < tracks.len() {
        push_chunk(ref out, TAG_MTRK, tracks.at(k).span());
        k += 1;
    }
    out
}

/// Canonical score as a Standard MIDI File, packed 31 bytes per felt with the byte length first
/// (`koji::midi::output::to_felt252_array` layout).
pub fn v3_score_midi(beast: PackableBeastV3, live: BeastV3LiveState) -> Array<felt252> {
    let params = map_v3_beast_to_composition_params(beast, live);
    let form = build_beast_form(params, beast_sound_seed(beast.id, beast.prefix, beast.suffix));
    koji::midi::output::to_felt252_array(beast_form_to_smf_bytes(@form, params.tempo_us))
}

// ─────────────────────────────────────────────────────────────
// BSN1: compact note stream (smallest client payload)
// ─────────────────────────────────────────────────────────────
//
// What varies per note in a Beast score is only its key: starts sit on a beat grid, every note in
// a score has the same sounding duration, voices play runs of consecutive beats, and velocity
// follows the articulation rule (base, +20 on every 4th note of a section when accented, capped at
// the ceiling). BSN1 sends the rule once and 7 bits per note:
//
//   header : version 8 | tempo_us 24 | grid_ticks 12 | duration_ticks 12 | articulation 3
//            | base_velocity 7 | velocity_ceiling 7 | run_count 8                   (81 bits)
//   run    : voice 4 | start_beat 12 | note_count 8                                 (24 bits)
//   note   : key 7
//
// Runs appear in emission order (section by section, voices ascending), so a run whose voice is
// not above the previous run's voice starts a new section. Bits are MSB-first, zero-padded to a
// byte, then packed 31 bytes per felt after a byte-length felt (`to_felt252_array`).
// `decodeBsn` in web/beast_sound/engine.js rebuilds the exact canonical events and MIDI bytes.

pub const BSN_VERSION: u8 = 1;

#[derive(Drop)]
struct BitWriter {
    bytes: Array<u8>,
    acc: u64,
    nbits: u32,
}

fn bw_new() -> BitWriter {
    BitWriter { bytes: array![], acc: 0, nbits: 0 }
}

fn pow2_u64(n: u32) -> u64 {
    // Lookup instead of a loop: the bit writer calls this for every field.
    let table: [u64; 33] = [
        1,
        2,
        4,
        8,
        16,
        32,
        64,
        128,
        256,
        512,
        1024,
        2048,
        4096,
        8192,
        16384,
        32768,
        65536,
        131072,
        262144,
        524288,
        1048576,
        2097152,
        4194304,
        8388608,
        16777216,
        33554432,
        67108864,
        134217728,
        268435456,
        536870912,
        1073741824,
        2147483648,
        4294967296,
    ];
    *table.span().at(n)
}

/// Append the low `width` bits of `value` (width <= 24).
fn bw_push(ref w: BitWriter, value: u32, width: u32) {
    let v: u64 = value.into();
    assert(v < pow2_u64(width), 'bsn field overflow');
    w.acc = w.acc * pow2_u64(width) + v;
    w.nbits += width;
    while w.nbits >= 8 {
        let shift = pow2_u64(w.nbits - 8);
        w.bytes.append((w.acc / shift).try_into().unwrap());
        w.acc = w.acc % shift;
        w.nbits -= 8;
    }
}

fn bw_finish(mut w: BitWriter) -> Array<u8> {
    if w.nbits > 0 {
        let pad = 8 - w.nbits;
        let byte: u64 = w.acc * pow2_u64(pad);
        w.bytes.append(byte.try_into().unwrap());
    }
    w.bytes
}

/// Encode a Beast form as BSN1 bytes.
pub fn beast_form_to_bsn_bytes(form: @BeastForm, params: BeastCompositionParams) -> Array<u8> {
    let events = form.events.span();
    assert(events.len() > 0, 'empty score');
    let grid: u32 = koji::composition::beast_score::BEAST_TIME_UNIT;
    let duration = *events.at(0).duration;

    // Pass 1: validate the grid assumptions and count runs.
    let mut runs: u32 = 0;
    let mut i: u32 = 0;
    while i < events.len() {
        let e = *events.at(i);
        assert(e.time % grid == 0, 'bsn off grid');
        assert(e.duration == duration, 'bsn mixed duration');
        assert(e.pitch < 128, 'bsn bad key');
        let starts_run = if i == 0 {
            true
        } else {
            let p = *events.at(i - 1);
            p.voice_id != e.voice_id || p.time + grid != e.time
        };
        if starts_run {
            runs += 1;
        }
        i += 1;
    }

    let mut w = bw_new();
    bw_push(ref w, BSN_VERSION.into(), 8);
    bw_push(ref w, params.tempo_us, 24);
    bw_push(ref w, grid, 12);
    bw_push(ref w, duration, 12);
    bw_push(ref w, params.articulation_profile.into(), 3);
    bw_push(ref w, koji::composition::melodic_canon::DEFAULT_VELOCITY.into(), 7);
    bw_push(ref w, params.velocity_ceiling.into(), 7);
    bw_push(ref w, runs, 8);

    // Pass 2: runs.
    let mut start: u32 = 0;
    while start < events.len() {
        let first = *events.at(start);
        let mut end = start + 1;
        while end < events.len() {
            let p = *events.at(end - 1);
            let e = *events.at(end);
            if p.voice_id != e.voice_id || p.time + grid != e.time {
                break;
            }
            end += 1;
        }
        bw_push(ref w, first.voice_id, 4);
        bw_push(ref w, first.time / grid, 12);
        bw_push(ref w, end - start, 8);
        let mut k = start;
        while k < end {
            bw_push(ref w, (*events.at(k)).pitch.into(), 7);
            k += 1;
        }
        start = end;
    }
    // Trailer (after the runs, so older decoders ignore it): the form length in beats, so a client
    // rebuilds the exact MIDI file, End of Track included.
    let length_ticks = *form.length_ticks;
    assert(length_ticks % grid == 0, 'bsn length off grid');
    bw_push(ref w, length_ticks / grid, 12);
    bw_finish(w)
}

/// Canonical score as BSN1, packed `[byte_len, 31-byte chunks...]`.
pub fn v3_score_notes(beast: PackableBeastV3, live: BeastV3LiveState) -> Array<felt252> {
    let params = map_v3_beast_to_composition_params(beast, live);
    let form = build_beast_form(params, beast_sound_seed(beast.id, beast.prefix, beast.suffix));
    koji::midi::output::to_felt252_array(beast_form_to_bsn_bytes(@form, params))
}

// ─────────────────────────────────────────────────────────────
// BSI1: general instruction stream (any music, 62-bit instructions)
// ─────────────────────────────────────────────────────────────
//
// Fixed-width instructions, 4 per felt, the first in the most significant slot:
//   felt = i0·2^186 + i1·2^124 + i2·2^62 + i3   (unused trailing slots are 0)
//
//   op 2 HEADER  version 8 | ppq 16 | count 24 (instructions, header included) | 0 12
//   op 1 TEMPO   tempo_us 24 | 0 36
//   op 0 NOTE    time 20 | duration 20 | pitch 7 | velocity 7 | voice 4 | 0 2   (absolute ticks)
//
// Unlike BSN1 it assumes nothing about the score (no grid, any durations), at ~62 bits per note.
// Byte-identical to encodeBsi in offchain/beast-sound/src/bsi.js.

const P2: felt252 = 0x4;
const P4: felt252 = 0x10;
const P7: felt252 = 0x80;
const P8: felt252 = 0x100;
const P12: felt252 = 0x1000;
const P16: felt252 = 0x10000;
const P20: felt252 = 0x100000;
const P24: felt252 = 0x1000000;
const P36: felt252 = 0x1000000000;
const P62: felt252 = 0x4000000000000000;

fn bsi_push(ref out: Array<felt252>, ref acc: felt252, ref slot: u32, ins: felt252) {
    acc = acc * P62 + ins;
    slot += 1;
    if slot == 4 {
        out.append(acc);
        acc = 0;
        slot = 0;
    }
}

pub fn beast_form_to_bsi_felts(form: @BeastForm, tempo_us: u32) -> Array<felt252> {
    let events = form.events.span();
    let count: u32 = events.len() + 2;
    assert(count < 0x1000000, 'bsi too long');
    assert(tempo_us < 0x1000000, 'bsi bad tempo');
    let mut out: Array<felt252> = array![];
    let mut acc: felt252 = 0;
    let mut slot: u32 = 0;
    bsi_push(ref out, ref acc, ref slot, (((2 * P8 + 1) * P16 + 480) * P24 + count.into()) * P12);
    bsi_push(ref out, ref acc, ref slot, (P24 + tempo_us.into()) * P36);
    for i in 0..events.len() {
        let e = *events.at(i);
        assert(e.time < 0x100000, 'bsi time');
        assert(e.duration < 0x100000, 'bsi duration');
        assert(e.pitch < 128 && e.velocity < 128, 'bsi key');
        assert(e.voice_id < 16, 'bsi voice');
        let ins = ((((e.time.into() * P20 + e.duration.into()) * P7 + e.pitch.into()) * P7
            + e.velocity.into())
            * P4
            + e.voice_id.into())
            * P2;
        bsi_push(ref out, ref acc, ref slot, ins);
    }
    while slot != 0 {
        bsi_push(ref out, ref acc, ref slot, 0);
    }
    out
}

pub fn v3_score_instructions(beast: PackableBeastV3, live: BeastV3LiveState) -> Array<felt252> {
    let params = map_v3_beast_to_composition_params(beast, live);
    let form = build_beast_form(params, beast_sound_seed(beast.id, beast.prefix, beast.suffix));
    beast_form_to_bsi_felts(@form, params.tempo_us)
}
