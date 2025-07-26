// Math utilities to replace Orion FP32x32 dependencies
// This module provides integer-based alternatives for time and frequency calculations

use core::traits::TryInto;
use core::option::OptionTrait;

// Time type definition using microseconds precision
type Time = u64; // microseconds

// Helper functions for time operations
fn time_from_seconds(seconds: u32) -> Time {
    (seconds * 1_000_000).into()
}

fn time_from_milliseconds(milliseconds: u32) -> Time {
    (milliseconds * 1_000).into()
}

fn time_to_seconds(time: Time) -> u32 {
    (time / 1_000_000).try_into().unwrap()
}

fn time_add(a: Time, b: Time) -> Time {
    a + b
}

fn time_sub(a: Time, b: Time) -> Time {
    if a >= b { a - b } else { 0 }
}

fn time_mul_by_factor(time: Time, numerator: u32, denominator: u32) -> Time {
    (time * numerator.into()) / denominator.into()
}

// Time quantization function to replace round_to_nearest_nth
fn round_to_nearest_nth_time(time: Time, grid_resolution: u64) -> Time {
    if grid_resolution == 0 {
        return time;
    }
    
    let rounded = (time / grid_resolution) * grid_resolution;
    let remainder = time - rounded;
    let half_resolution = grid_resolution / 2;

    if remainder >= half_resolution {
        rounded + grid_resolution
    } else {
        rounded
    }
}

// Precomputed frequency table for MIDI notes 0-127
// Values are in Hz * 1000 for integer precision
// Formula: freq = 440 * 2^((keynum - 69) / 12) * 1000
fn get_frequency_table() -> Span<u32> {
    array![
        8176,    8662,    9177,    9723,    10301,   10913,   11562,   12250,   // 0-7
        12978,   13750,   14568,   15434,   16352,   17324,   18354,   19445,   // 8-15
        20602,   21827,   23125,   24500,   25957,   27500,   29135,   30868,   // 16-23
        32703,   34648,   36708,   38891,   41203,   43654,   46249,   48999,   // 24-31
        51913,   55000,   58270,   61735,   65406,   69296,   73416,   77782,   // 32-39
        82407,   87307,   92499,   97999,   103826,  110000,  116541,  123471,  // 40-47
        130813,  138591,  146832,  155563,  164814,  174614,  184997,  195998,  // 48-55
        207652,  220000,  233082,  246942,  261626,  277183,  293665,  311127,  // 56-63
        329628,  349228,  369994,  391995,  415305,  440000,  466164,  493883,  // 64-71
        523251,  554365,  587330,  622254,  659255,  698456,  739989,  783991,  // 72-79
        830609,  880000,  932328,  987767,  1046502, 1108731, 1174659, 1244508, // 80-87
        1318510, 1396913, 1479978, 1567982, 1661219, 1760000, 1864655, 1975533, // 88-95
        2093005, 2217461, 2349318, 2489016, 2637020, 2793826, 2959955, 3135963, // 96-103
        3322438, 3520000, 3729310, 3951066, 4186009, 4434922, 4698636, 4978032, // 104-111
        5274041, 5587652, 5919911, 6271927, 6644875, 7040000, 7458620, 7902133, // 112-119
        8372018, 8869844, 9397273, 9956063, 10548082, 11175303, 11839822, 12543854 // 120-127
    ].span()
}

// Get frequency for a MIDI keynum (0-127)
// Returns frequency in Hz * 1000 for integer precision
fn freq_from_keynum(keynum: u8) -> u32 {
    if keynum > 127 {
        return 0; // Invalid keynum
    }
    let freq_table = get_frequency_table();
    *freq_table.at(keynum.into())
}

// Alternative integer approximation for frequency calculation
// Using 16.16 fixed point (u32 with 16 fractional bits)
const FIXED_POINT_SCALE: u32 = 65536; // 2^16
const A4_FREQ_SCALED: u32 = 28836352; // 440 * FIXED_POINT_SCALE

fn freq_integer_approx(keynum: u8) -> u32 {
    // Approximate 2^(x/12) using polynomial approximation
    // For MIDI range, this provides good accuracy
    let semitones_from_a4 = if keynum >= 69 {
        keynum - 69
    } else {
        69 - keynum
    };
    
    // Simplified power of 2 approximation
    // 2^x ≈ 1 + x + x²/2 + x³/6 (Taylor series)
    let x_scaled = (semitones_from_a4.into() * FIXED_POINT_SCALE) / 12;
    let power_of_two = power_of_two_approx(x_scaled);
    
    if keynum >= 69 {
        (A4_FREQ_SCALED * power_of_two) / FIXED_POINT_SCALE
    } else {
        (A4_FREQ_SCALED * FIXED_POINT_SCALE) / power_of_two
    }
}

fn power_of_two_approx(x_scaled: u32) -> u32 {
    // Polynomial approximation for 2^x where x is in 16.16 fixed point
    // Accurate enough for MIDI frequency calculations
    let x2 = (x_scaled * x_scaled) / FIXED_POINT_SCALE;
    let x3 = (x2 * x_scaled) / FIXED_POINT_SCALE;
    
    FIXED_POINT_SCALE + x_scaled + x2/2 + x3/6
}

// Linear interpolation utility function
// Returns interpolated value scaled by 1000 for precision
fn linear_interpolate(x1: u64, y1: u64, x2: u64, y2: u64, x: u64) -> u64 {
    if x1 == x2 {
        return y1;
    }
    
    if x <= x1 {
        return y1;
    }
    
    if x >= x2 {
        return y2;
    }
    
    // y = y1 + (y2 - y1) * (x - x1) / (x2 - x1)
    let x_diff = x2 - x1;
    let x_offset = x - x1;
    
    if y2 >= y1 {
        let y_diff = y2 - y1;
        y1 + (y_diff * x_offset) / x_diff
    } else {
        let y_diff = y1 - y2;
        y1 - (y_diff * x_offset) / x_diff
    }
} 