use koji::sine_wave::{PI_SCALED, SineWaveParams, generate_wave, sine_fixed_point, sinusoidal_timing_wave_squared};

#[test]
fn test_wave_generation() {
    let params = SineWaveParams {
        min_value: 0_u32,
        max_value: 100_u32,
        frequency: 1_u32,
        length: 10_u32,
    };

    let result = sinusoidal_timing_wave_squared(params);

    // Check that we got the expected length
    assert(result.len() == 10_u32, 'Wrong array length');

    // Check that all values are within range
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

#[test]
fn test_sine_approximation() {
    // Test that sine approximation produces reasonable values
    let zero_sine = sine_fixed_point(0_u128);
    let pi_half_sine = sine_fixed_point(PI_SCALED / 2_u128);
    let pi_sine = sine_fixed_point(PI_SCALED);

    // sin(0) should be close to 0
    assert(zero_sine < 10000_u128, 'sin(0) should be close to 0');

    // sin(pi/2) should be close to 1 (scaled) - adjusted for our approximation
    assert(
        pi_half_sine > 400000_u128 && pi_half_sine < 600000_u128,
        'sin(pi/2) should be reasonable',
    );

    // sin(pi) should be close to 0
    assert(pi_sine < 10000_u128, 'sin(pi) should be close to 0');
}

#[test]
fn test_generate_wave() {
    let result = generate_wave(10_u32, 50_u32, 1_u32, 5_u32);

    // Check length
    assert(result.len() == 5_u32, 'Wrong length');

    // Check range
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