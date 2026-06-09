//! Barry Harris deterministic 6th-diminished harmony engine.
//!
//! See `docs/barry_harris_spec.md`.

use core::array::ArrayTrait;
use core::hash::HashStateTrait;
use core::poseidon::PoseidonTrait;
use core::traits::TryInto;
use koji::composition::barry_profiles::{
    barry_lcg_from_seed, max_tension_for_profile, pick_rule, BarryRuleProfile,
};
use koji::composition::barry_rules::{
    advance_beat, allowed_rules_for_beat, apply_rule, beat_role, melody_constraints_for_state,
    tension_for_rule,
};
use koji::composition::melodic_canon::NoteEvent;
use koji::composition::voice_leading::{harmony_target, HarmonicTimeline};
use koji::rng::{LCGRandomSource, bounded};

pub const BARRY_PC_MOD: u32 = 12;
pub const BARRY_SCALE_LEN: u32 = 8;
pub const BARRY_MAX_PHRASE_STEPS: u32 = 64;
pub const BARRY_DEFAULT_VOICES: u32 = 4;
pub const BARRY_HARRIS_V1_PLAN_ID: felt252 = 'barry_harris_v1';

#[derive(Copy, Drop, PartialEq)]
pub enum ChordFamily {
    Major6Dim,
    Minor6Dim,
    Dominant7Dim,
    Diminished,
}

#[derive(Copy, Drop, PartialEq)]
pub enum BarryRule {
    Stay,
    ScaleStepUp,
    ScaleStepDown,
    DiminishedInterpolation,
    HalfStepApproachUp,
    HalfStepApproachDown,
    FamilyRotation,
    InversionShiftUp,
    InversionShiftDown,
    ResolveToStable,
}

#[derive(Copy, Drop, PartialEq)]
pub enum BeatRole {
    Strong,
    Weak,
    Passing,
    Approach,
}

#[derive(Drop)]
pub struct HarmonicState {
    pub tonic_pc: u8,
    pub family: ChordFamily,
    pub inversion: u8,
    pub beat_phase: u8,
    pub tension_level: u8,
    pub active_pcs: Array<u8>,
    pub register_hint: i16,
    pub previous_state_hash: felt252,
}

#[derive(Drop)]
pub struct BarryVoicing {
    pub notes: Array<i16>,
}

#[derive(Drop)]
pub struct BarryPhrase {
    pub states: Array<HarmonicState>,
    pub voicings: Array<BarryVoicing>,
    pub melody_constraints: Array<Array<u8>>,
}

#[derive(Drop)]
pub struct BarryTraits {
    pub tonic_pc: u8,
    pub family: ChordFamily,
    pub profile: BarryRuleProfile,
    pub peak_tension: u8,
    pub step_count: u32,
}

pub fn pc_add(pc: u8, interval: u8) -> u8 {
    let r: u32 = pc.into();
    let i: u32 = interval.into();
    ((r + i) % BARRY_PC_MOD).try_into().unwrap()
}

pub fn pc_sub(pc: u8, interval: u8) -> u8 {
    let r: u32 = pc.into();
    let i: u32 = interval.into();
    let v = if r >= i { r - i } else { r + BARRY_PC_MOD - i };
    (v % BARRY_PC_MOD).try_into().unwrap()
}

pub fn normalize_pc(value: u32) -> u8 {
    (value % BARRY_PC_MOD).try_into().unwrap()
}

pub fn contains_pc(pcs: Span<u8>, pc: u8) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= pcs.len() {
            break;
        }
        if *pcs.at(i) == pc {
            return true;
        }
        i += 1;
    };
    false
}

fn append_pc(ref out: Array<u8>, tonic: u8, interval: u8) {
    out.append(pc_add(tonic, interval));
}

pub fn major_6_dim_scale(tonic_pc: u8) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    append_pc(ref out, tonic_pc, 0);
    append_pc(ref out, tonic_pc, 2);
    append_pc(ref out, tonic_pc, 4);
    append_pc(ref out, tonic_pc, 5);
    append_pc(ref out, tonic_pc, 7);
    append_pc(ref out, tonic_pc, 8);
    append_pc(ref out, tonic_pc, 9);
    append_pc(ref out, tonic_pc, 11);
    out
}

pub fn minor_6_dim_scale(tonic_pc: u8) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    append_pc(ref out, tonic_pc, 0);
    append_pc(ref out, tonic_pc, 2);
    append_pc(ref out, tonic_pc, 3);
    append_pc(ref out, tonic_pc, 5);
    append_pc(ref out, tonic_pc, 7);
    append_pc(ref out, tonic_pc, 8);
    append_pc(ref out, tonic_pc, 9);
    append_pc(ref out, tonic_pc, 11);
    out
}

pub fn dominant_7_dim_scale(tonic_pc: u8) -> Array<u8> {
    let mut out: Array<u8> = ArrayTrait::new();
    append_pc(ref out, tonic_pc, 0);
    append_pc(ref out, tonic_pc, 1);
    append_pc(ref out, tonic_pc, 3);
    append_pc(ref out, tonic_pc, 4);
    append_pc(ref out, tonic_pc, 6);
    append_pc(ref out, tonic_pc, 7);
    append_pc(ref out, tonic_pc, 9);
    append_pc(ref out, tonic_pc, 10);
    out
}

pub fn scale_for_family(tonic_pc: u8, family: ChordFamily) -> Array<u8> {
    match family {
        ChordFamily::Major6Dim => major_6_dim_scale(tonic_pc),
        ChordFamily::Minor6Dim => minor_6_dim_scale(tonic_pc),
        ChordFamily::Dominant7Dim => dominant_7_dim_scale(tonic_pc),
        ChordFamily::Diminished => {
            let mut out: Array<u8> = ArrayTrait::new();
            append_pc(ref out, tonic_pc, 0);
            append_pc(ref out, tonic_pc, 3);
            append_pc(ref out, tonic_pc, 6);
            append_pc(ref out, tonic_pc, 9);
            append_pc(ref out, tonic_pc, 1);
            append_pc(ref out, tonic_pc, 4);
            append_pc(ref out, tonic_pc, 7);
            append_pc(ref out, tonic_pc, 10);
            out
        },
    }
}

pub fn stable_chord_tones_for(tonic_pc: u8, family: ChordFamily) -> Array<u8> {
    let t = tonic_pc;
    let mut out: Array<u8> = ArrayTrait::new();
    match family {
        ChordFamily::Major6Dim => {
            append_pc(ref out, t, 0);
            append_pc(ref out, t, 4);
            append_pc(ref out, t, 7);
            append_pc(ref out, t, 9);
        },
        ChordFamily::Minor6Dim => {
            append_pc(ref out, t, 0);
            append_pc(ref out, t, 3);
            append_pc(ref out, t, 7);
            append_pc(ref out, t, 9);
        },
        ChordFamily::Dominant7Dim => {
            append_pc(ref out, t, 0);
            append_pc(ref out, t, 4);
            append_pc(ref out, t, 7);
            append_pc(ref out, t, 10);
        },
        ChordFamily::Diminished => {
            append_pc(ref out, t, 0);
            append_pc(ref out, t, 3);
            append_pc(ref out, t, 6);
            append_pc(ref out, t, 9);
        },
    };
    out
}

pub fn stable_chord_tones(state: @HarmonicState) -> Array<u8> {
    stable_chord_tones_for(*state.tonic_pc, *state.family)
}

pub fn diminished_connector_tones(state: @HarmonicState) -> Array<u8> {
    let t = *state.tonic_pc;
    let mut out: Array<u8> = ArrayTrait::new();
    match *state.family {
        ChordFamily::Major6Dim | ChordFamily::Minor6Dim => {
            append_pc(ref out, t, 2);
            append_pc(ref out, t, 5);
            append_pc(ref out, t, 8);
            append_pc(ref out, t, 11);
        },
        ChordFamily::Dominant7Dim | ChordFamily::Diminished => {
            append_pc(ref out, t, 1);
            append_pc(ref out, t, 3);
            append_pc(ref out, t, 6);
            append_pc(ref out, t, 9);
        },
    };
    out
}

pub fn state_hash(state: @HarmonicState) -> felt252 {
    let mut h = PoseidonTrait::new();
    h = h.update((*state.tonic_pc).into());
    h = h.update(family_felt(*state.family));
    h = h.update((*state.inversion).into());
    h = h.update((*state.beat_phase).into());
    h = h.update((*state.tension_level).into());
    h = h.update((*state.register_hint).into());
    let mut i: usize = 0;
    loop {
        if i >= state.active_pcs.len() {
            break;
        }
        h = h.update((*state.active_pcs.at(i)).into());
        i += 1;
    };
    h.finalize()
}

fn family_felt(family: ChordFamily) -> felt252 {
    match family {
        ChordFamily::Major6Dim => 0,
        ChordFamily::Minor6Dim => 1,
        ChordFamily::Dominant7Dim => 2,
        ChordFamily::Diminished => 3,
    }
}

pub fn initial_harmonic_state(tonic_pc: u8, family: ChordFamily) -> HarmonicState {
    let active_pcs = stable_chord_tones_for(tonic_pc, family);
    HarmonicState {
        tonic_pc,
        family,
        inversion: 0,
        beat_phase: 0,
        tension_level: 0,
        active_pcs,
        register_hint: 60,
        previous_state_hash: 0,
    }
}

pub fn voicelead(
    previous_voicing: Span<i16>,
    target_pcs: Span<u8>,
    register_min: i16,
    register_max: i16,
    tie_break: u32,
) -> Array<i16> {
    let voice_count = if target_pcs.len() == 0 {
        0
    } else if previous_voicing.len() > target_pcs.len() {
        previous_voicing.len()
    } else {
        target_pcs.len()
    };
    let mut out: Array<i16> = ArrayTrait::new();
    let mut vi: usize = 0;
    loop {
        if vi >= voice_count {
            break;
        }
        let pc = *target_pcs.at(vi % target_pcs.len());
        let prev = if vi < previous_voicing.len() {
            *previous_voicing.at(vi)
        } else {
            register_min + 12
        };
        let best = best_keynum_for_pc(pc, prev, register_min, register_max, tie_break + vi.try_into().unwrap());
        out.append(best);
        vi += 1;
    };
    out
}

fn best_keynum_for_pc(
    pc: u8, prev: i16, register_min: i16, register_max: i16, tie_break: u32,
) -> i16 {
    let mut k: i16 = register_min;
    let mut best_k: i16 = register_min;
    let mut best_cost: u32 = 999999;
    let mut tie_rank: u32 = 0;
    loop {
        if k > register_max {
            break;
        }
        let ku: u32 = if k >= 0 {
            k.try_into().unwrap()
        } else {
            0
        };
        if normalize_pc(ku) == pc {
            let cost = abs_i16(k - prev);
            let rank = bounded(tie_break + tie_rank, 1000000);
            if cost < best_cost || (cost == best_cost && rank < bounded(tie_break, 1000000)) {
                best_cost = cost;
                best_k = k;
            }
            tie_rank += 1;
        }
        k += 1;
    };
    best_k
}

fn abs_i16(v: i16) -> u32 {
    if v < 0 {
        (-v).try_into().unwrap()
    } else {
        v.try_into().unwrap()
    }
}

pub fn generate_barry_phrase(
    seed: felt252,
    tonic_pc: u8,
    family: ChordFamily,
    length_steps: u32,
    profile: BarryRuleProfile,
    register_min: i16,
    register_max: i16,
) -> BarryPhrase {
    let steps = if length_steps > BARRY_MAX_PHRASE_STEPS {
        BARRY_MAX_PHRASE_STEPS
    } else if length_steps == 0 {
        1
    } else {
        length_steps
    };
    let mut rng = barry_lcg_from_seed(seed);
    let mut state = initial_harmonic_state(tonic_pc, family);
    let mut states: Array<HarmonicState> = ArrayTrait::new();
    let mut voicings: Array<BarryVoicing> = ArrayTrait::new();
    let mut melody_constraints: Array<Array<u8>> = ArrayTrait::new();
    let mut prev_notes: Array<i16> = ArrayTrait::new();
    let max_tension = max_tension_for_profile(profile);

    let mut step: u32 = 0;
    loop {
        if step >= steps {
            break;
        }
        let prev_hash = state_hash(@state);
        state.previous_state_hash = prev_hash;

        let constraints = melody_constraints_for_state(@state);
        melody_constraints.append(constraints);

        let (raw, nr) = LCGRandomSource::draw(@rng);
        rng = nr;
        let notes = voicelead(
            prev_notes.span(), state.active_pcs.span(), register_min, register_max, raw,
        );
        voicings.append(BarryVoicing { notes: clone_i16_array(notes.span()) });
        prev_notes = notes;
        states.append(clone_harmonic_state(@state));

        let role = beat_role(state.beat_phase);
        let allowed = allowed_rules_for_beat(role, state.tension_level, max_tension);
        let (rule, next_rng2) = pick_rule(rng, profile, allowed);
        rng = next_rng2;
        let prev_tension = state.tension_level;
        let prev_beat = state.beat_phase;
        let mut next = apply_rule(state, rule);
        next.tension_level = saturating_tension(prev_tension, tension_for_rule(rule));
        if next.tension_level > max_tension {
            next = apply_rule(next, BarryRule::ResolveToStable);
            next.tension_level = 0;
        }
        next.beat_phase = advance_beat(prev_beat);
        state = next;
        step += 1;
    };

    BarryPhrase { states, voicings, melody_constraints }
}

fn saturating_tension(current: u8, delta: i8) -> u8 {
    if delta >= 0 {
        let d: u8 = delta.try_into().unwrap();
        if current > 255 - d {
            255
        } else {
            current + d
        }
    } else {
        let d: u8 = (-delta).try_into().unwrap();
        if current < d {
            0
        } else {
            current - d
        }
    }
}

fn clone_harmonic_state(state: @HarmonicState) -> HarmonicState {
    let mut pcs: Array<u8> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= state.active_pcs.len() {
            break;
        }
        pcs.append(*state.active_pcs.at(i));
        i += 1;
    };
    HarmonicState {
        tonic_pc: *state.tonic_pc,
        family: *state.family,
        inversion: *state.inversion,
        beat_phase: *state.beat_phase,
        tension_level: *state.tension_level,
        active_pcs: pcs,
        register_hint: *state.register_hint,
        previous_state_hash: *state.previous_state_hash,
    }
}

fn clone_i16_array(src: Span<i16>) -> Array<i16> {
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= src.len() {
            break;
        }
        out.append(*src.at(i));
        i += 1;
    };
    out
}

pub fn barry_phrase_to_harmonic_timeline(phrase: @BarryPhrase) -> HarmonicTimeline {
    let mut targets = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= phrase.states.len() {
            break;
        }
        let st = phrase.states.at(i);
        let mut pcs: Array<u8> = ArrayTrait::new();
        let mut j: usize = 0;
        loop {
            if j >= st.active_pcs.len() {
                break;
            }
            pcs.append(*st.active_pcs.at(j));
            j += 1;
        };
        targets.append(harmony_target(pcs));
        i += 1;
    };
    HarmonicTimeline { targets }
}

pub fn barry_phrase_to_note_events(phrase: @BarryPhrase, grid_unit: u32) -> Array<NoteEvent> {
    let mut out: Array<NoteEvent> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= phrase.voicings.len() {
            break;
        }
        let v = phrase.voicings.at(i);
        let time: u32 = i.try_into().unwrap() * grid_unit;
        let mut j: usize = 0;
        loop {
            if j >= v.notes.len() {
                break;
            }
            let kn: i16 = *v.notes.at(j);
            let pitch: u8 = if kn >= 0 {
                kn.try_into().unwrap()
            } else {
                0
            };
            out.append(NoteEvent { time, duration: grid_unit, pitch, velocity: 80, voice_id: j.try_into().unwrap() });
            j += 1;
        };
        i += 1;
    };
    out
}

pub fn barry_traits_from_phrase(
    phrase: @BarryPhrase, profile: BarryRuleProfile,
) -> BarryTraits {
    let mut peak: u8 = 0;
    let mut i: usize = 0;
    loop {
        if i >= phrase.states.len() {
            break;
        }
        let t = *phrase.states.at(i).tension_level;
        if t > peak {
            peak = t;
        }
        i += 1;
    };
    let tonic = if phrase.states.len() > 0 {
        *phrase.states.at(0).tonic_pc
    } else {
        0
    };
    let family = if phrase.states.len() > 0 {
        *phrase.states.at(0).family
    } else {
        ChordFamily::Major6Dim
    };
    BarryTraits {
        tonic_pc: tonic,
        family,
        profile,
        peak_tension: peak,
        step_count: phrase.states.len().try_into().unwrap(),
    }
}

pub fn phrase_state_tonic_at(phrase: @BarryPhrase, index: usize) -> u8 {
    *phrase.states.at(index).tonic_pc
}

pub fn scales_equal(a: Span<u8>, b: Span<u8>) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut i: usize = 0;
    loop {
        if i >= a.len() {
            break;
        }
        if *a.at(i) != *b.at(i) {
            return false;
        }
        i += 1;
    };
    true
}
