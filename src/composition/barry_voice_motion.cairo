//! Barry Harris v2 voice-motion policies for polyphonic realization.
//!
//! See `docs/barry_harris_v2.md` §BH13.

use core::array::ArrayTrait;
use core::traits::TryInto;
use koji::composition::barry_harris::voicelead;
use koji::rng::bounded;

pub use koji::composition::barry_v2_types::VoiceMotionPolicy;

fn abs_i16(v: i16) -> u32 {
    if v < 0 {
        (-v).try_into().unwrap()
    } else {
        v.try_into().unwrap()
    }
}

fn motion_sign(delta: i16) -> i8 {
    if delta > 0 {
        1
    } else if delta < 0 {
        -1
    } else {
        0
    }
}

fn total_abs_motion(previous: Span<i16>, candidate: Span<i16>) -> u32 {
    let n = if previous.len() < candidate.len() {
        previous.len()
    } else {
        candidate.len()
    };
    let mut total: u32 = 0;
    let mut i: usize = 0;
    loop {
        if i >= n {
            break;
        }
        total += abs_i16(*candidate.at(i) - *previous.at(i));
        i += 1;
    };
    total
}

pub fn score_voice_motion(
    previous: Span<i16>, candidate: Span<i16>, policy: VoiceMotionPolicy,
) -> u32 {
    let base = total_abs_motion(previous, candidate);
    if previous.len() == 0 || candidate.len() == 0 {
        return base;
    }
    let penalty: u32 = match policy {
        VoiceMotionPolicy::MinimalMotion => 0,
        VoiceMotionPolicy::Parallel => parallel_penalty(previous, candidate),
        VoiceMotionPolicy::ContraryOuterVoices => contrary_outer_penalty(previous, candidate),
        VoiceMotionPolicy::ContraryBassMelody => contrary_bass_melody_penalty(previous, candidate),
        VoiceMotionPolicy::ObliqueTopVoice => oblique_top_penalty(previous, candidate),
        VoiceMotionPolicy::ObliqueBass => oblique_bass_penalty(previous, candidate),
    };
    base + penalty
}

fn parallel_penalty(previous: Span<i16>, candidate: Span<i16>) -> u32 {
    let n = candidate.len();
    let mut moving: u32 = 0;
    let mut same_sign: u32 = 0;
    let mut first_sign: i8 = 0;
    let mut i: usize = 0;
    loop {
        if i >= n {
            break;
        }
        let delta = *candidate.at(i) - *previous.at(i);
        let sign = motion_sign(delta);
        if sign != 0 {
            moving += 1;
            if moving == 1 {
                first_sign = sign;
            } else if sign == first_sign {
                same_sign += 1;
            }
        }
        i += 1;
    };
    if moving <= 1 {
        0
    } else if same_sign + 1 >= moving {
        0
    } else {
        500
    }
}

fn contrary_outer_penalty(previous: Span<i16>, candidate: Span<i16>) -> u32 {
    if candidate.len() < 2 {
        return 0;
    }
    let bass_delta = *candidate.at(0) - *previous.at(0);
    let top_idx = candidate.len() - 1;
    let top_delta = *candidate.at(top_idx) - *previous.at(top_idx);
    let contrary = motion_sign(bass_delta) != 0
        && motion_sign(top_delta) != 0
        && motion_sign(bass_delta) != motion_sign(top_delta);
    if contrary {
        0
    } else {
        400
    }
}

fn contrary_bass_melody_penalty(previous: Span<i16>, candidate: Span<i16>) -> u32 {
    contrary_outer_penalty(previous, candidate)
}

fn oblique_top_penalty(previous: Span<i16>, candidate: Span<i16>) -> u32 {
    if candidate.len() == 0 {
        return 0;
    }
    let top_idx = candidate.len() - 1;
    if *candidate.at(top_idx) == *previous.at(top_idx) {
        0
    } else {
        300
    }
}

fn oblique_bass_penalty(previous: Span<i16>, candidate: Span<i16>) -> u32 {
    if candidate.len() == 0 {
        return 0;
    }
    if *candidate.at(0) == *previous.at(0) {
        0
    } else {
        300
    }
}

fn voices_crossed(voicing: Span<i16>) -> bool {
    let mut i: usize = 1;
    loop {
        if i >= voicing.len() {
            break;
        }
        if *voicing.at(i) < *voicing.at(i - 1) {
            return true;
        }
        i += 1;
    };
    false
}

pub fn voicelead_with_policy(
    previous_voicing: Span<i16>,
    target_pcs: Span<u8>,
    register_min: i16,
    register_max: i16,
    policy: VoiceMotionPolicy,
    tie_break: u32,
) -> Array<i16> {
    if policy == VoiceMotionPolicy::MinimalMotion {
        return voicelead(previous_voicing, target_pcs, register_min, register_max, tie_break);
    }
    let base = voicelead(previous_voicing, target_pcs, register_min, register_max, tie_break);
    let mut best = clone_i16(base.span());
    let mut best_score = score_voice_motion(previous_voicing, best.span(), policy);
    let mut shift: i32 = -2;
    loop {
        if shift > 2 {
            break;
        }
        let candidate = shift_voicing_octaves(base.span(), shift);
        if voices_crossed(candidate.span()) {
            shift += 1;
            continue;
        }
        let in_range = voicing_in_register(candidate.span(), register_min, register_max);
        if in_range {
            let score = score_voice_motion(previous_voicing, candidate.span(), policy);
            let rank = bounded(tie_break + shift.try_into().unwrap() + 100, 1000000);
            if score < best_score
                || (score == best_score && rank < bounded(tie_break, 1000000)) {
                best_score = score;
                best = candidate;
            }
        }
        shift += 1;
    };
    best
}

fn voicing_in_register(voicing: Span<i16>, register_min: i16, register_max: i16) -> bool {
    let mut i: usize = 0;
    loop {
        if i >= voicing.len() {
            break;
        }
        let k = *voicing.at(i);
        if k < register_min || k > register_max {
            return false;
        }
        i += 1;
    };
    true
}

fn shift_voicing_octaves(voicing: Span<i16>, octaves: i32) -> Array<i16> {
    let delta: i16 = (octaves * 12).try_into().unwrap();
    let mut out: Array<i16> = ArrayTrait::new();
    let mut i: usize = 0;
    loop {
        if i >= voicing.len() {
            break;
        }
        out.append(*voicing.at(i) + delta);
        i += 1;
    };
    out
}

fn clone_i16(src: Span<i16>) -> Array<i16> {
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

pub fn voices_do_not_cross(voicing: Span<i16>) -> bool {
    !voices_crossed(voicing)
}
