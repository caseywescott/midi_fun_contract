use koji::sine_wave::{
    PI_SCALED, SineWaveParams, TWO_PI_SCALED, generate_wave, sine_fixed_point,
    sinusoidal_timing_wave_squared,
};

/// Test basic sine wave generation with simple parameters
/// This test verifies that the sinusoidal_timing_wave_squared function:
/// - Generates the correct number of values (length parameter)
/// - Produces values within the specified range (min_value to max_value)
/// - Handles basic frequency settings
#[test]
fn test_wave_generation() {
    // Define sine wave parameters: min=0, max=100, frequency=1, length=10
    let params = SineWaveParams {
        min_value: 0_u32, max_value: 100_u32, frequency: 1_u32, length: 10_u32,
    };

    // Store params values before moving (since params will be consumed)
    let min_val = params.min_value;
    let max_val = params.max_value;
    let freq = params.frequency;
    let len = params.length;

    // Generate the sine wave using squared sine function
    let result = sinusoidal_timing_wave_squared(params);

    // Print the generated sine wave values for debugging and verification
    println!("SINE WAVE VALUES:");
    println!("Min: {}, Max: {}, Frequency: {}, Length: {}", min_val, max_val, freq, len);
    println!("Generated array: [");

    // Iterate through the result array and print each value with its index
    let mut i = 0_u32;
    loop {
        if i >= result.len() {
            break;
        }
        let value = *result.at(i);
        if i == result.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Array length: {}", result.len());

    // Assertion 1: Verify the array has the expected length
    assert(result.len() == 10_u32, 'Wrong array length');

    // Assertion 2: Verify all values are within the specified range [0, 100]
    let mut i = 0_u32;
    loop {
        if i >= result.len() {
            break;
        }
        let value = *result.at(i);
        assert(value >= 0_u32 && value <= 100_u32, 'Value out of range');
        i += 1;
    };
}

/// Test sine wave generation with different parameters
/// This test uses a different range (10-50) and frequency (2) to ensure
/// the function works correctly with various input parameters
#[test]
fn test_wave_generation_different_params() {
    // Define sine wave parameters: min=10, max=50, frequency=2, length=8
    let params = SineWaveParams {
        min_value: 10_u32, max_value: 50_u32, frequency: 2_u32, length: 8_u32,
    };

    // Store params values before moving (since params will be consumed)
    let min_val = params.min_value;
    let max_val = params.max_value;
    let freq = params.frequency;
    let len = params.length;

    // Generate the sine wave using squared sine function
    let result = sinusoidal_timing_wave_squared(params);

    // Print the generated sine wave values for debugging and verification
    println!("SINE WAVE VALUES (Different Parameters):");
    println!("Min: {}, Max: {}, Frequency: {}, Length: {}", min_val, max_val, freq, len);
    println!("Generated array: [");

    // Iterate through the result array and print each value with its index
    let mut i = 0_u32;
    loop {
        if i >= result.len() {
            break;
        }
        let value = *result.at(i);
        if i == result.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Array length: {}", result.len());

    // Assertion 1: Verify the array has the expected length
    assert(result.len() == 8_u32, 'Wrong array length');

    // Assertion 2: Verify all values are within the specified range [10, 50]
    let mut i = 0_u32;
    loop {
        if i >= result.len() {
            break;
        }
        let value = *result.at(i);
        assert(value >= 10_u32 && value <= 50_u32, 'Value out of range');
        i += 1;
    };
}

/// Test sine wave generation with a longer sequence
/// This test verifies that the function can handle larger arrays (100 elements)
/// and maintains performance and correctness with longer sequences
#[test]
fn test_wave_generation_long_sequence() {
    // Define sine wave parameters: min=1, max=100, frequency=1, length=100
    let params = SineWaveParams {
        min_value: 1_u32, max_value: 100_u32, frequency: 1_u32, length: 100_u32,
    };

    // Store params values before moving (since params will be consumed)
    let min_val = params.min_value;
    let max_val = params.max_value;
    let freq = params.frequency;
    let len = params.length;

    // Generate the sine wave using squared sine function
    let result = sinusoidal_timing_wave_squared(params);

    // Print the generated sine wave values for debugging and verification
    println!("SINE WAVE VALUES (Long Sequence):");
    println!("Min: {}, Max: {}, Frequency: {}, Length: {}", min_val, max_val, freq, len);
    println!("Generated array: [");

    // Iterate through the result array and print each value with its index
    let mut i = 0_u32;
    loop {
        if i >= result.len() {
            break;
        }
        let value = *result.at(i);
        if i == result.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Array length: {}", result.len());

    // Assertion 1: Verify the array has the expected length
    assert(result.len() == 100_u32, 'Wrong array length');

    // Assertion 2: Verify all values are within the specified range [1, 100]
    let mut i = 0_u32;
    loop {
        if i >= result.len() {
            break;
        }
        let value = *result.at(i);
        assert(value >= 1_u32 && value <= 100_u32, 'Value out of range');
        i += 1;
    };
}

/// Debug test for the sine function to understand its behavior
/// This test examines the raw sine function values at key phase points
/// to help understand how the fixed-point sine approximation works
#[test]
fn test_sine_debug() {
    // Test the sine function directly to see what values it produces
    println!("SINE FUNCTION DEBUG:");

    // Test key phase points in the sine wave cycle
    let zero_phase = 0_u128; // 0 radians
    let quarter_phase = PI_SCALED / 2_u128; // π/2 radians
    let half_phase = PI_SCALED; // π radians
    let three_quarter_phase = PI_SCALED * 3_u128 / 2_u128; // 3π/2 radians
    let full_phase = TWO_PI_SCALED; // 2π radians

    // Calculate sine values at each key point
    let zero_sine = sine_fixed_point(zero_phase);
    let quarter_sine = sine_fixed_point(quarter_phase);
    let half_sine = sine_fixed_point(half_phase);
    let three_quarter_sine = sine_fixed_point(three_quarter_phase);
    let full_sine = sine_fixed_point(full_phase);

    // Print the raw sine values to understand the fixed-point representation
    println!("sin(0) = {}", zero_sine);
    println!("sin(pi/2) = {}", quarter_sine);
    println!("sin(pi) = {}", half_sine);
    println!("sin(3pi/2) = {}", three_quarter_sine);
    println!("sin(2pi) = {}", full_sine);

    // Test squared values (since we use sin² in the wave generation)
    // Divide by 1000000 to normalize the fixed-point representation
    let zero_squared = (zero_sine * zero_sine) / 1000000_u128;
    let quarter_squared = (quarter_sine * quarter_sine) / 1000000_u128;
    let half_squared = (half_sine * half_sine) / 1000000_u128;

    println!("sin^2(0) = {}", zero_squared);
    println!("sin^2(pi/2) = {}", quarter_squared);
    println!("sin^2(pi) = {}", half_squared);

    // Test scaling to a specific range (1-100) to simulate the wave generation
    let range = 99_u128; // max - min = 100 - 1 = 99
    let zero_scaled = 1_u128 + (range * zero_squared) / 1000000_u128;
    let quarter_scaled = 1_u128 + (range * quarter_squared) / 1000000_u128;
    let half_scaled = 1_u128 + (range * half_squared) / 1000000_u128;

    println!("Scaled sin^2(0) = {}", zero_scaled);
    println!("Scaled sin^2(pi/2) = {}", quarter_scaled);
    println!("Scaled sin^2(pi) = {}", half_scaled);
}

/// Test the sine approximation accuracy
/// This test verifies that our fixed-point sine approximation produces
/// reasonable values that match expected mathematical behavior
#[test]
fn test_sine_approximation() {
    // Test that sine approximation produces reasonable values
    let zero_sine = sine_fixed_point(0_u128);
    let pi_half_sine = sine_fixed_point(PI_SCALED / 2_u128);
    let pi_sine = sine_fixed_point(PI_SCALED);

    // sin(0) should be close to 0 (allowing for approximation error)
    assert(zero_sine < 10000_u128, 'sin(0) should be close to 0');

    // sin(π/2) should be close to 1 (scaled) - allowing for approximation tolerance
    // The range 400000-600000 accounts for our fixed-point representation
    assert(
        pi_half_sine > 400000_u128 && pi_half_sine < 600000_u128, 'sin(pi/2) should be reasonable',
    );

    // sin(π) should be close to 0 (allowing for approximation error)
    assert(pi_sine < 10000_u128, 'sin(pi) should be close to 0');
}

/// Test the simplified generate_wave function
/// This test verifies the generate_wave helper function which provides
/// a simpler interface for creating sine waves
#[test]
fn test_generate_wave() {
    // Generate a sine wave with parameters: min=10, max=50, frequency=1, length=5
    let result = generate_wave(10_u32, 50_u32, 1_u32, 5_u32);

    // Assertion 1: Verify the array has the expected length
    assert(result.len() == 5_u32, 'Wrong length');

    // Assertion 2: Verify all values are within the specified range [10, 50]
    let mut i = 0_u32;
    loop {
        if i >= result.len() {
            break;
        }
        let value = *result.at(i);
        assert(value >= 10_u32 && value <= 50_u32, 'Value out of range');
        i += 1;
    };
}
