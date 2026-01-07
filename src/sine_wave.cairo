use core::array::ArrayTrait;
use core::option::OptionTrait;

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

// Improved sine approximation that returns values in [0, SCALE] range
// This provides better scaling for the squared sine wave
pub fn sine_fixed_point(x_scaled: u128) -> u128 {
    // Normalize x to [0, 2π]
    let x_normalized = x_scaled % TWO_PI_SCALED;

    // Convert to [0, π] range for calculation
    let x = if x_normalized > PI_SCALED {
        TWO_PI_SCALED - x_normalized
    } else {
        x_normalized
    };

    // Improved sine approximation that produces values in [0, SCALE] range
    // For small angles, sin(x) ≈ x
    // For larger angles, we use a better curve approximation
    let x_ratio = x * 1000_u128 / PI_SCALED; // Scale to 0-1000 range

    if x_ratio <= 500_u128 {
        // For first half of π, use improved linear approximation
        // Scale to full range: x goes from 0 to π/2, result goes from 0 to SCALE
        (x * SCALE) / (PI_SCALED / 2_u128)
    } else {
        // For second half of π, use inverted approximation
        // Scale to full range: x goes from π/2 to π, result goes from SCALE to 0
        ((PI_SCALED - x) * SCALE) / (PI_SCALED / 2_u128)
    }
}

// Main function to generate squared sine wave
pub fn sinusoidal_timing_wave_squared(params: SineWaveParams) -> Array<u32> {
    let mut result = ArrayTrait::new();
    let range = params.max_value - params.min_value;

    let mut i: u32 = 0;
    loop {
        if i >= params.length {
            break;
        }

        // Calculate phase: (i / length) * frequency * 2 * PI
        // This ensures frequency=1 gives exactly one cycle over the length
        let numerator = i.into() * params.frequency.into() * TWO_PI_SCALED;
        let phase = numerator / params.length.into();

        // Calculate sine value using our approximation
        let sine_value = sine_fixed_point(phase);

        // Square the sine value and normalize to [0, SCALE] range
        let squared_value = (sine_value * sine_value) / SCALE;

        // Scale to the desired range: minValue + range * (squaredValue / SCALE)
        let scaled_value = (range.into() * squared_value) / SCALE;
        let final_value = params.min_value + scaled_value.try_into().unwrap();

        result.append(final_value);
        i += 1;
    }

    result
}

// Helper function for easy usage
pub fn generate_wave(min_val: u32, max_val: u32, freq: u32, len: u32) -> Array<u32> {
    let params = SineWaveParams {
        min_value: min_val, max_value: max_val, frequency: freq, length: len,
    };
    sinusoidal_timing_wave_squared(params)
}

// Example usage function
pub fn example_usage() -> Array<u32> {
    // Generate a wave with values between 10 and 100, frequency 2, length 20
    generate_wave(10_u32, 100_u32, 2_u32, 20_u32)
}
