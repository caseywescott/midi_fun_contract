// Math utilities to replace Orion FP32x32 dependencies
// This module provides integer-based alternatives for time and frequency calculations

use core::traits::TryInto;
use core::option::OptionTrait;

// Time type definition using microseconds precision
pub type Time = u64; // microseconds

// Helper functions for u8 operations
pub fn min_u8(a: u8, b: u8) -> u8 {
    if a < b { a } else { b }
}

// Helper functions for time operations
pub fn time_from_seconds(seconds: u32) -> Time {
    (seconds * 1_000_000).into()
}

pub fn time_from_milliseconds(milliseconds: u32) -> Time {
    (milliseconds * 1_000).into()
}

pub fn time_to_seconds(time: Time) -> u32 {
    (time / 1_000_000).try_into().unwrap()
}

pub fn time_add(a: Time, b: Time) -> Time {
    a + b
}

pub fn time_sub(a: Time, b: Time) -> Time {
    if a >= b { a - b } else { 0 }
}

pub fn time_mul_by_factor(time: Time, numerator: u32, denominator: u32) -> Time {
    if denominator == 0 {
        time
    } else {
        (time * numerator.into()) / denominator.into()
    }
}

pub fn round_to_nearest_nth_time(time: Time, grid_resolution: u32) -> Time {
    if grid_resolution == 0 {
        time
    } else {
        let resolution: Time = grid_resolution.into();
        (time + resolution / 2) / resolution * resolution
    }
}

// Frequency calculation using lookup table
pub fn freq_from_keynum(keynum: u8) -> u32 {
    // Precomputed frequency table for MIDI notes 0-127 (Hz * 1000 for integer precision)
    let frequencies = array![
        8175, 8661, 9177, 9722, 10300, 10913, 11562, 12249, 12978, 13750, 14567, 15433,
        16351, 17323, 18354, 19445, 20601, 21826, 23124, 24499, 25956, 27500, 29135, 30867,
        32703, 34647, 36708, 38890, 41203, 43653, 46249, 48999, 51913, 55000, 58270, 61735,
        65406, 69295, 73416, 77781, 82406, 87307, 92498, 97998, 103826, 110000, 116540, 123470,
        130812, 138591, 146832, 155563, 164813, 174614, 184997, 195997, 207652, 220000, 233081, 246941,
        261625, 277182, 293664, 311126, 329627, 349228, 369994, 391995, 415304, 440000, 466163, 493883,
        523251, 554365, 587329, 622253, 659255, 698456, 739988, 783991, 830609, 880000, 932327, 987766,
        1046502, 1108731, 1174659, 1244507, 1318510, 1396913, 1479978, 1567982, 1661219, 1760000, 1864655, 1975533,
        2093005, 2217461, 2349318, 2489016, 2637020, 2793826, 2959955, 3135963, 3322438, 3520000, 3729310, 3951066,
        4186009, 4434922, 4698636, 4978032, 5274041, 5587652, 5919911, 6271927, 6644875, 7040000, 7458620, 7902133,
        8372018, 8869844, 9397273, 9956063, 10548082, 11175303, 11839822, 12543854
    ];
    
    if keynum >= 127 {
        *frequencies.at(127)
    } else {
        *frequencies.at(keynum.into())
    }
}

// Linear interpolation for velocity curves
pub fn linear_interpolate(x1: Time, y1: u64, x2: Time, y2: u64, x: Time) -> u64 {
    if x1 == x2 {
        y1
    } else if x <= x1 {
        y1
    } else if x >= x2 {
        y2
    } else {
        let range_x = x2 - x1;
        let range_y = if y2 >= y1 { y2 - y1 } else { y1 - y2 };
        let offset_x = x - x1;
        
        if y2 >= y1 {
            y1 + (range_y * offset_x) / range_x
        } else {
            y1 - (range_y * offset_x) / range_x
        }
    }
} 