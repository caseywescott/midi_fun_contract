# Orion Library Replacement Guide

This guide provides step-by-step instructions for replacing the deprecated Orion library dependencies (`FP32x32`, `Tensor`, etc.) in the MIDI contract.

## Overview of Current Usage

The Orion library is currently used in the following areas:

1. **Time representation** - FP32x32 for MIDI timing and velocity curves
2. **Frequency calculations** - Mathematical operations with exp2()
3. **Tensor operations** - For velocity curve manipulations
4. **Time quantization** - Rounding operations

## Replacement Strategy

### 1. Time Representation Replacement

**Current Usage**: `FP32x32` for time values in MIDI messages and velocity curves

**Replacement**: Use scaled integer arithmetic with a fixed precision factor

```cairo
// New time representation using u64 with microsecond precision
// This gives us ~580,000 years of range with microsecond precision
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
```

### 2. Frequency Calculation Replacement

**Current Usage**: Complex FP32x32 math with exp2() for frequency calculation

**Replacement Option A**: Lookup table (Recommended for accuracy and performance)

```cairo
// Precomputed frequency table for MIDI notes 0-127
// Values are in Hz * 1000 for integer precision
fn get_frequency_table() -> Span<u32> {
    array![
        8176,    8662,    9177,    9723,    10301,   10913,   11562,   12250,
        12978,   13750,   14568,   15434,   16352,   17324,   18354,   19445,
        20602,   21827,   23125,   24500,   25957,   27500,   29135,   30868,
        // ... continue for all 128 MIDI notes
        // Formula: freq = 440 * 2^((keynum - 69) / 12) * 1000
    ].span()
}

fn freq_from_keynum(keynum: u8) -> u32 {
    if keynum > 127 {
        return 0; // Invalid keynum
    }
    let freq_table = get_frequency_table();
    *freq_table.at(keynum.into())
}
```

**Replacement Option B**: Integer approximation (For dynamic calculation)

```cairo
// Fixed-point arithmetic implementation for frequency calculation
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
```

### 3. Time Quantization Replacement

**Current Usage**: `round_to_nearest_nth` function using FP32x32

**Replacement**:

```cairo
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
```

### 4. Velocity Curve Replacement

**Current Usage**: Tensor operations and FP32x32 for velocity curves

**Replacement**: Array-based implementation with integer math

```cairo
#[derive(Copy, Drop, Clone)]
struct VelocityCurve {
    times: Span<Time>,
    levels: Span<u8>
}

// Linear interpolation for velocity curves
fn interpolate_velocity(curve: @VelocityCurve, time_index: Time) -> Option<u8> {
    let times = *curve.times;
    let levels = *curve.levels;

    if times.len() == 0 || times.len() != levels.len() {
        return Option::None(());
    }

    // Find the interpolation points
    let mut i = 0;
    loop {
        if i >= times.len() - 1 {
            break;
        }

        let t1 = *times.at(i);
        let t2 = *times.at(i + 1);

        if time_index >= t1 && time_index <= t2 {
            let v1: u64 = (*levels.at(i)).into();
            let v2: u64 = (*levels.at(i + 1)).into();

            // Linear interpolation: v1 + (v2 - v1) * (t - t1) / (t2 - t1)
            let time_ratio = ((time_index - t1) * 1000) / (t2 - t1); // Scale for precision
            let value_diff = if v2 >= v1 { v2 - v1 } else { v1 - v2 };

            let interpolated = if v2 >= v1 {
                v1 + (value_diff * time_ratio) / 1000
            } else {
                v1 - (value_diff * time_ratio) / 1000
            };

            return Option::Some(interpolated.try_into().unwrap());
        }

        i += 1;
    };

    Option::None(())
}
```

## Implementation Steps

### Step 1: Update Type Definitions

1. **Update `src/midi/types.cairo`**:
   - Replace `FP32x32` with `Time` (u64) in all message structs
   - Remove `use orion::numbers::FP32x32;`

### Step 2: Create Utility Functions

1. **Create `src/midi/math.cairo`**:
   - Add the time helper functions
   - Add the frequency calculation functions
   - Add the interpolation functions

### Step 3: Update Core Functions

1. **Update `src/midi/pitch.cairo`**:

   - Replace the `freq` function with lookup table or integer approximation
   - Remove Orion imports
   - Update function signatures to use new types

2. **Update `src/midi/time.cairo`**:

   - Replace `round_to_nearest_nth` implementation
   - Remove Orion imports

3. **Update `src/midi/velocitycurve.cairo`**:

   - Replace tensor operations with array-based operations
   - Update all functions to use `Time` instead of `FP32x32`
   - Remove Orion imports

4. **Update `src/midi/core.cairo`**:
   - Remove Orion imports
   - Update all function implementations
   - Add imports for new math utilities

### Step 4: Update Dependencies

1. **Update `Scarb.toml`**:
   - Remove the orion dependency

### Step 5: Update Tests

1. **Update test files**:
   - Replace FP32x32 usage with new Time type
   - Update test cases to use integer values
   - Verify accuracy of new implementations

## Migration Checklist

- [ ] Create `src/midi/math.cairo` with utility functions
- [ ] Update `src/midi/types.cairo` to use `Time` type
- [ ] Replace frequency calculation in `src/midi/pitch.cairo`
- [ ] Update time quantization in `src/midi/time.cairo`
- [ ] Replace tensor operations in `src/midi/velocitycurve.cairo`
- [ ] Update `src/midi/core.cairo` imports and implementations
- [ ] Remove orion dependency from `Scarb.toml`
- [ ] Update all test files
- [ ] Verify compilation and functionality

## Notes and Considerations

1. **Precision Trade-offs**: The integer-based approach may have slightly different precision than floating-point. Test critical calculations to ensure acceptable accuracy.

2. **Performance**: Lookup tables are faster than calculations but use more memory. Choose based on your performance requirements.

3. **Range Limits**: The new `Time` type (u64 microseconds) provides ~580,000 years of range, which should be sufficient for MIDI applications.

4. **Backwards Compatibility**: This is a breaking change. All existing code using FP32x32 types will need to be updated.

5. **Testing**: Thoroughly test frequency calculations against known values to ensure the replacement maintains musical accuracy.

## Example: Complete File Update

Here's an example of how `src/midi/pitch.cairo` would look after migration:

```cairo
// Remove these imports:
// use orion::numbers::{FP32x32, FP32x32Impl, FixedTrait};

// Add this import:
use koji::midi::math::{freq_from_keynum};

// Update the freq function:
fn freq(pc: PitchClass) -> u32 {
    let keynum = pc.keynum();
    freq_from_keynum(keynum)
}
```

This approach provides a complete, dependency-free replacement for the Orion library while maintaining the mathematical accuracy needed for MIDI applications.
