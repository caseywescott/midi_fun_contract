use core::array::ArrayTrait;
use core::option::OptionTrait;
use core::traits::TryInto;

// Fixed-point arithmetic constants
pub const SCALE: u128 = 1000000_u128; // 6 decimal places for precision
pub const PI_SCALED: u128 = 3141592_u128; // PI * SCALE
pub const TWO_PI_SCALED: u128 = 6283184_u128; // 2 * PI * SCALE

#[derive(Drop, Serde)]
pub struct SineWaveParams {
    pub min_value: u32,
    pub max_value: u32,
    pub frequency: u32,
    pub length: u32,
}

/// Smooth sin(x) on [0, π]: 4·x·(π−x)/π² — rounded peak at π/2, zero at 0 and π.
fn sine_magnitude_on_pi(x_on_pi: u128) -> u128 {
    let x = if x_on_pi > PI_SCALED {
        PI_SCALED
    } else {
        x_on_pi
    };

    let pi_minus_x = PI_SCALED - x;
    let num = 4_u128 * x * pi_minus_x * SCALE;
    let denom = PI_SCALED * PI_SCALED;
    num / denom
}

/// Signed sin(x) approximation in [-SCALE, SCALE].
pub fn sine_signed_fixed_point(x_scaled: u128) -> i128 {
    let x_normalized = x_scaled % TWO_PI_SCALED;
    if x_normalized <= PI_SCALED {
        let mag: i128 = sine_magnitude_on_pi(x_normalized).try_into().unwrap();
        mag
    } else {
        let mag: i128 = sine_magnitude_on_pi(x_normalized - PI_SCALED).try_into().unwrap();
        -mag
    }
}

/// (sin(x) + 1) / 2 scaled to [0, SCALE] — always non-negative.
pub fn sine_offset_positive_fixed_point(x_scaled: u128) -> u128 {
    let signed = sine_signed_fixed_point(x_scaled);
    let scale_i: i128 = SCALE.try_into().unwrap();
    let offset: i128 = (signed + scale_i) / 2;
    offset.try_into().unwrap()
}

/// Legacy non-negative fold (|sin| on one half-period). Prefer `sine_signed_fixed_point`.
pub fn sine_fixed_point(x_scaled: u128) -> u128 {
    sine_magnitude_on_pi(x_scaled % PI_SCALED)
}

/// Generate a wave from true sin(x), offset to [0, 1] then scaled to [min_value, max_value].
/// Unlike the squared variant, this rises and falls through the range each cycle.
pub fn sinusoidal_timing_wave(params: SineWaveParams) -> Array<u32> {
    let mut result = ArrayTrait::new();
    let range = params.max_value - params.min_value;

    let mut i: u32 = 0;
    loop {
        if i >= params.length {
            break;
        }

        let numerator = i.into() * params.frequency.into() * TWO_PI_SCALED;
        let phase = numerator / params.length.into();

        let offset_positive = sine_offset_positive_fixed_point(phase);
        let scaled_value = (range.into() * offset_positive) / SCALE;
        let final_value = params.min_value + scaled_value.try_into().unwrap();

        result.append(final_value);
        i += 1;
    }

    result
}

/// |sin(x)|² envelope (always rises from min toward max). Kept for callers that want a
/// non-negative-only contour.
pub fn sinusoidal_timing_wave_squared(params: SineWaveParams) -> Array<u32> {
    let mut result = ArrayTrait::new();
    let range = params.max_value - params.min_value;

    let mut i: u32 = 0;
    loop {
        if i >= params.length {
            break;
        }

        let numerator = i.into() * params.frequency.into() * TWO_PI_SCALED;
        let phase = numerator / params.length.into();

        let sine_value = sine_magnitude_on_pi(phase % PI_SCALED);
        let squared_value = (sine_value * sine_value) / SCALE;
        let scaled_value = (range.into() * squared_value) / SCALE;
        let final_value = params.min_value + scaled_value.try_into().unwrap();

        result.append(final_value);
        i += 1;
    }

    result
}

/// Helper: true offset sine wave (not squared).
pub fn generate_wave(min_val: u32, max_val: u32, freq: u32, len: u32) -> Array<u32> {
    let params = SineWaveParams {
        min_value: min_val, max_value: max_val, frequency: freq, length: len,
    };
    sinusoidal_timing_wave(params)
}

// Example usage function
pub fn example_usage() -> Array<u32> {
    generate_wave(10_u32, 100_u32, 2_u32, 20_u32)
}

// ── Tempo rubato helpers ──
// Wave values use offset sine: min ≈ sin trough, max ≈ sin peak, midpoint ≈ sin zero-crossing.

pub const TIMING_WAVE_MIN: u32 = 1;
pub const TIMING_WAVE_MAX: u32 = 100;
pub const TIMING_WAVE_REF: u32 = 50;

/// Same parameters as `test_wave_generation_long_sequence`: min=1, max=100, frequency=1.
pub fn long_sequence_timing_wave(length: u32) -> Array<u32> {
    long_sequence_timing_wave_freq(length, 1_u32)
}

/// Offset-sine timing wave with explicit cycle count over `length` structural beats.
pub fn long_sequence_timing_wave_freq(length: u32, frequency: u32) -> Array<u32> {
    generate_wave(TIMING_WAVE_MIN, TIMING_WAVE_MAX, frequency, length)
}

/// Scale a tick duration by a wave sample (1 = fastest, 100 = slowest, 50 = unchanged).
pub fn scale_duration_by_wave(base_ticks: u32, wave_value: u32) -> u32 {
    let scaled: u32 = (base_ticks.into() * wave_value.into() / TIMING_WAVE_REF)
        .try_into()
        .unwrap();
    if scaled == 0 {
        1_u32
    } else {
        scaled
    }
}

/// Cumulative start tick at each structural beat boundary. `out.len() == wave.len() + 1`;
/// `out[t]` is the scaled start of beat `t`.
pub fn cumulative_beat_starts(wave: Span<u32>, unit: u32) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    out.append(0_u32);
    let mut cum: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= wave.len() {
            break;
        }
        cum += scale_duration_by_wave(unit, *wave.at(i));
        out.append(cum);
        i += 1;
    };
    out
}

/// Cumulative tick at the start of leader structural beat `s` (sum of scaled beats 0..s−1).
pub fn struct_beat_starts(wave: Span<u32>, unit: u32) -> Array<u32> {
    cumulative_beat_starts(wave, unit)
}

/// Total tick span through `num_beats` structural beats.
pub fn textured_span_ticks(wave: Span<u32>, unit: u32, num_beats: u32) -> u32 {
    let starts = struct_beat_starts(wave, unit);
    if num_beats >= starts.len() {
        *starts.at(starts.len() - 1)
    } else {
        *starts.at(num_beats)
    }
}

/// Total tick span across all beats in `wave` (one full cycle).
pub fn total_scaled_span(wave: Span<u32>, unit: u32) -> u32 {
    textured_span_ticks(wave, unit, wave.len())
}

// ── Modal run contour (pitch + duration share the same sin sample) ──

pub const MODAL_CONTOUR_MIN: u32 = 0;
pub const MODAL_CONTOUR_MAX: u32 = 35;
pub const MODAL_CONTOUR_LEN: u32 = 100;
pub const MODAL_CONTOUR_FREQ: u32 = 2;

/// Sin contour for modal runs — oscillates through the range twice over 100 notes.
pub fn modal_contour_wave() -> Array<u32> {
    generate_wave(MODAL_CONTOUR_MIN, MODAL_CONTOUR_MAX, MODAL_CONTOUR_FREQ, MODAL_CONTOUR_LEN)
}

/// Map contour height to note length in microseconds (linear: min + contour × step).
pub fn contour_to_duration_us(contour_value: u32, min_us: u64, step_us: u64) -> u64 {
    min_us + contour_value.into() * step_us
}

/// Symmetric note length: longest at peak and trough, shortest at the midpoint crossing.
/// Keeps both extrema visually rounded in the piano roll.
pub fn contour_to_duration_symmetric_us(
    contour_value: u32, contour_min: u32, contour_max: u32, min_us: u64, max_us: u64,
) -> u64 {
    let mid = (contour_min + contour_max) / 2;
    let half_span = if contour_max > contour_min {
        (contour_max - contour_min) / 2
    } else {
        1_u32
    };
    let cv: u32 = contour_value;
    let dist = if cv >= mid {
        cv - mid
    } else {
        mid - cv
    };
    let range_us = max_us - min_us;
    let dur = min_us + (range_us * dist.into() / half_span.into());
    if dur > max_us {
        max_us
    } else {
        dur
    }
}
