//! Canonical musical inputs. No NFT layout, storage, payment or evolution policy.
//! Uses only the compiler-provided Starknet builtins, so managers can share exact
//! types/Store derives without the engine's compiler/player dependency graph.

pub const EDITION_COMPOSITION_CONFIG_VERSION: u16 = 1;
pub const COMPOSER_INPUTS_VERSION: u16 = 4;
pub const GENERATION_INPUTS_VERSION: u16 = 2;
pub const MAX_TEMPO_US: u32 = 1048575;

/// Immutable deterministic edition-template configuration. Clock and sale policy
/// belong to the manager; this seed is not purchase/staff randomness.
#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct EditionCompositionConfig {
    pub composition_seed: felt252,
}

/// Static musical identity supplied by a manager, without NFT layout or flags.
#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct BeastMusicalIdentity {
    pub species_id: u64,
    pub name_variant_id: u16,
    pub tier: u8,
    pub family: u8,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct MusicIdentity {
    pub source_species_id: u64,
    pub name_variant_id: u16,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct ThemeInputs {
    pub motif_seed: felt252,
    pub tier: u8,
    pub register_band: u8,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct ScoreInputs {
    pub mode_id: u8,
    pub tonic_keynum: u8,
    pub tier: u8,
    pub weakness: u8,
    pub voice_count: u8,
    pub section_count: u8,
    pub stretto_lag: u8,
    pub use_inversion: bool,
    pub use_countersubject: bool,
    pub ornament_density: u8,
    pub articulation_profile: u8,
    pub velocity_ceiling: u8,
    pub tempo_us: u32,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct TreatmentInputs {
    pub rhythm_seed: felt252,
    pub flip_side: bool,
    /// 0 sequence, 1 stretto, 2 inversion.
    pub development: u8,
    /// 0 alternating, 1 rising, 2 falling.
    pub direction: u8,
    /// 0 wide, 1 normal, 2 close.
    pub spacing: u8,
    pub trill: bool,
    pub prominence: u8,
    /// Choose independent supported rhythm cells per section; false repeats the written phrase.
    pub section_rhythm: bool,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
#[allow(starknet::store_no_default_variant)]
pub enum ChannelPolicy {
    Genesis,
    Seeded: felt252,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
#[allow(starknet::store_no_default_variant)]
pub enum SpecialArrangement {
    None,
    /// The ornament profile's name identity, separate from score/program identity.
    Yeti: u16,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct ArrangementInputs {
    pub family: u8,
    pub identity: MusicIdentity,
    pub channel_count: u8,
    pub channel_policy: ChannelPolicy,
    pub special: SpecialArrangement,
    pub top_lead: bool,
    pub balanced: bool,
    pub weak_ties: bool,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct SongInputs {
    pub theme: ThemeInputs,
    pub score: ScoreInputs,
    pub treatment: TreatmentInputs,
    pub arrangement: ArrangementInputs,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct SoundCheckInputs {
    pub identity: MusicIdentity,
    pub mode_id: u8,
    pub tonic_keynum: u8,
    pub family: u8,
    pub tempo_us: u32,
    pub velocity_ceiling: u8,
    pub articulation_profile: u8,
}

/// Variant order is canonical: SoundCheck=0, Song=1.
#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
#[allow(starknet::store_no_default_variant)]
pub enum ComposerInputs {
    SoundCheck: SoundCheckInputs,
    Song: SongInputs,
}

/// Immutable, complete musical base snapshotted for an internally generated sample.
#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct GenerationInputs {
    pub base_song: SongInputs,
}

/// Canonical named evolution identity. Paid generation never applies the
/// shared Species Song39/40 source swap, and score/program name0 is separate.
pub fn normalize_generation_identity(x: BeastMusicalIdentity) -> MusicIdentity {
    let identity = MusicIdentity {
        source_species_id: x.species_id, name_variant_id: x.name_variant_id,
    };
    validate_identity(identity);
    assert(x.tier >= 1 && x.tier <= 5, 'invalid musical tier');
    assert(x.family <= 2, 'invalid program family');
    identity
}

pub fn validate_identity(x: MusicIdentity) {
    assert(x.source_species_id != 0, 'invalid music identity');
    assert(x.name_variant_id <= 1242, 'invalid music name');
}

pub fn validate_mode(mode: u8) {
    assert(
        mode == 4 || mode == 5 || mode == 6 || mode == 7 || mode == 8 || mode == 26,
        'unsupported musical mode',
    );
}

pub fn validate_articulation(profile: u8) {
    assert(
        profile == 0 || profile == 1 || profile == 2 || profile == 3 || profile == 5,
        'invalid articulation',
    );
}

pub fn validate_performance(sound_effects: u8) {
    assert(sound_effects <= 3, 'invalid sound effects');
}

fn validate_performance_base(tempo_us: u32, velocity: u8, articulation: u8) {
    assert(tempo_us >= 1 && tempo_us <= MAX_TEMPO_US, 'invalid musical tempo');
    assert(velocity >= 1 && velocity <= 127, 'invalid musical velocity');
    validate_articulation(articulation);
}

pub fn validate_song(x: SongInputs) {
    let p = x.score;
    validate_identity(x.arrangement.identity);
    validate_mode(p.mode_id);
    assert(x.theme.tier >= 1 && x.theme.tier <= 5, 'invalid theme tier');
    assert(x.theme.register_band <= 2, 'invalid theme register');
    assert(p.tier >= 1 && p.tier <= 5, 'invalid musical tier');
    // Existing modal song realizer's supported home range, before octave voices.
    assert(p.tonic_keynum >= 24 && p.tonic_keynum <= 96, 'invalid song tonic');
    assert(p.weakness <= 2, 'invalid rhythm family');
    assert(p.voice_count >= 1 && p.voice_count <= 4, 'invalid voice count');
    assert(p.section_count >= 1 && p.section_count <= 5, 'invalid section count');
    assert(p.stretto_lag >= 1 && p.stretto_lag <= 4, 'invalid entry lag');
    assert(p.ornament_density <= 7, 'invalid ornament density');
    validate_performance_base(p.tempo_us, p.velocity_ceiling, p.articulation_profile);
    assert(x.treatment.development <= 2, 'invalid development');
    assert(x.treatment.direction <= 2, 'invalid episode direction');
    assert(x.treatment.spacing <= 2, 'invalid voice spacing');
    assert(x.treatment.prominence <= 3, 'invalid prominence');
    assert(x.arrangement.family <= 2, 'invalid program family');
    let roles = p.voice_count + if p.use_countersubject {
        1
    } else {
        0
    } + 1;
    assert(
        x.arrangement.channel_count >= 1 && x.arrangement.channel_count <= roles,
        'invalid channel count',
    );
    if let SpecialArrangement::Yeti(name) = x.arrangement.special {
        assert(name <= 1242, 'invalid ornament name');
    }
}

pub fn validate_inputs(x: ComposerInputs) {
    match x {
        ComposerInputs::Song(song) => validate_song(song),
        ComposerInputs::SoundCheck(check) => {
            validate_identity(check.identity);
            validate_mode(check.mode_id);
            // Highest Sound Check degree is 14 = tonic + two octaves.
            assert(check.tonic_keynum <= 103, 'invalid sound check tonic');
            assert(check.family <= 2, 'invalid program family');
            validate_performance_base(
                check.tempo_us, check.velocity_ceiling, check.articulation_profile,
            );
        },
    }
}

pub fn validate_generation_inputs(x: GenerationInputs) {
    validate_song(x.base_song);
}

/// Full scalar Serde, prefixed by codec version; no opaque recipe payload.
pub fn encode_inputs(x: ComposerInputs) -> Array<felt252> {
    validate_inputs(x);
    let mut values = array![COMPOSER_INPUTS_VERSION.into()];
    Serde::serialize(@x, ref values);
    values
}

pub fn decode_inputs(mut values: Span<felt252>) -> ComposerInputs {
    let original = values;
    let version = *values.pop_front().expect('missing inputs version');
    assert(version == COMPOSER_INPUTS_VERSION.into(), 'unknown inputs version');
    let x: ComposerInputs = Serde::deserialize(ref values).expect('invalid inputs encoding');
    assert(values.is_empty(), 'extra inputs data');
    validate_inputs(x);
    assert(encode_inputs(x).span() == original, 'non canonical inputs');
    x
}

pub fn encode_generation_inputs(x: GenerationInputs) -> Array<felt252> {
    validate_generation_inputs(x);
    let mut values = array![GENERATION_INPUTS_VERSION.into()];
    Serde::serialize(@x, ref values);
    values
}

pub fn decode_generation_inputs(mut values: Span<felt252>) -> GenerationInputs {
    let original = values;
    let version = *values.pop_front().expect('missing generation version');
    assert(version == GENERATION_INPUTS_VERSION.into(), 'unknown generation version');
    let x: GenerationInputs = Serde::deserialize(ref values).expect('invalid generation data');
    assert(values.is_empty(), 'extra generation data');
    validate_generation_inputs(x);
    assert(encode_generation_inputs(x).span() == original, 'non canonical generation');
    x
}

pub mod evolution;

#[cfg(test)]
mod tests;
