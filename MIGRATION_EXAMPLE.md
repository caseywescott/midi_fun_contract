# Migration Example: pitch.cairo

This document shows a concrete example of how to migrate the `pitch.cairo` file from using Orion FP32x32 to the new integer-based math utilities.

## Before Migration

```cairo
use core::option::OptionTrait;
use array::ArrayTrait;
use array::SpanTrait;
use clone::Clone;
use array::ArrayTCloneImpl;
use traits::TryInto;
use traits::Into;
use debug::PrintTrait;

use koji::midi::types::{Modes, PitchClass, OCTAVEBASE, Direction, Quality};
use koji::midi::modes::{mode_steps};

use orion::numbers::{FP32x32, FP32x32Impl, FixedTrait}; // ← Remove this line

// ... other code ...

fn freq(pc: PitchClass) -> u32 {
    let keynum = pc.keynum();
    let a = FP32x32 { mag: 440, sign: false };
    let numsemitones = FP32x32 { mag: 12, sign: false };

    let mut keynumscale = FP32x32 { mag: 0, sign: true };
    if (keynum > 69) {
        keynumscale = FP32x32 { mag: (keynum - 69).into(), sign: false };
    } else {
        keynumscale =
            FP32x32 {
                mag: (69 - keynum).into(), sign: false
            }; // currently not allowing negative values
    };
    let keynumscaleratio = keynumscale / numsemitones;
    let freq = a * keynumscaleratio.exp2();
    freq.mag.try_into().unwrap()
}
```

## After Migration

```cairo
use core::option::OptionTrait;
use array::ArrayTrait;
use array::SpanTrait;
use clone::Clone;
use array::ArrayTCloneImpl;
use traits::TryInto;
use traits::Into;
use debug::PrintTrait;

use koji::midi::types::{Modes, PitchClass, OCTAVEBASE, Direction, Quality};
use koji::midi::modes::{mode_steps};
use koji::midi::math::{freq_from_keynum}; // ← Add this line

// ... other code remains the same ...

fn freq(pc: PitchClass) -> u32 {
    let keynum = pc.keynum();
    // Return frequency in Hz * 1000 for integer precision
    // To get actual Hz, divide by 1000
    freq_from_keynum(keynum)
}
```

## Key Changes

1. **Removed**: `use orion::numbers::{FP32x32, FP32x32Impl, FixedTrait};`
2. **Added**: `use koji::midi::math::{freq_from_keynum};`
3. **Simplified**: The entire `freq` function now uses a simple lookup table

## Benefits

- **No floating point dependencies**: Pure integer arithmetic
- **Better performance**: Lookup table is faster than exponential calculations
- **Accuracy**: Precomputed values ensure consistent, precise frequencies
- **Simplicity**: Much simpler code that's easier to understand and maintain

## Testing the Change

You can verify the change works correctly by testing known MIDI frequencies:

```cairo
#[test]
fn test_frequency_calculations() {
    // Test A4 (MIDI 69) = 440 Hz
    let a4 = PitchClass { note: 9, octave: 4 }; // A4
    let freq_millihertz = a4.freq();
    let freq_hz = freq_millihertz / 1000;
    assert(freq_hz == 440, 'A4 should be 440 Hz');

    // Test Middle C (MIDI 60) ≈ 261.626 Hz
    let middle_c = PitchClass { note: 0, octave: 4 }; // C4
    let freq_millihertz = middle_c.freq();
    let freq_hz = freq_millihertz / 1000;
    assert(freq_hz == 261, 'Middle C should be ~261 Hz');
}
```

## Next Steps

After updating `pitch.cairo`, continue with:

1. Update `src/midi/types.cairo` to use `Time` instead of `FP32x32`
2. Update `src/midi/time.cairo` to use the new quantization function
3. Update `src/midi/velocitycurve.cairo` to remove tensor dependencies
4. Update `src/midi/core.cairo` to use new imports
5. Remove orion dependency from `Scarb.toml`
6. Update all test files
