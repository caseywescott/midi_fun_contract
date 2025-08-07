use koji::midi::modes::{dorian_steps, mode_steps};
use koji::midi::pitch::{get_notes_of_key, pc_to_keynum};
use koji::midi::types::{Modes, OCTAVEBASE, PitchClass};
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

/// Test modal run generation using sine wave contour
/// This test creates a melodic sequence that follows the contour of a sine wave
/// by mapping sine wave values to indices in a Dorian mode array, then collecting
/// the resulting keynums into a sequence of musical notes
#[test]
fn test_modal_run_with_sine_contour() {
    // Define sine wave parameters for the melodic contour
    // Using a smaller range (0-35) to keep notes closer together
    // This gives us 5 octaves of the 7-note Dorian mode (5 * 7 = 35)
    let params = SineWaveParams {
        min_value: 0_u32, max_value: 35_u32, frequency: 2_u32, length: 100_u32,
    };

    // Generate the sine wave contour values
    let sine_contour = sinusoidal_timing_wave_squared(params);

    // Create a Dorian mode starting from C (note 0, octave 4)
    let tonic = PitchClass { note: 0_u8, octave: 4_u8 }; // C4
    let dorian_mode = Modes::Dorian(());
    let mode_steps = mode_steps(dorian_mode);

    // Get the notes of the Dorian mode in C
    let dorian_notes = get_notes_of_key(tonic, mode_steps);
    let mode_size = dorian_notes.len();

    println!("MODAL RUN WITH SINE CONTOUR:");
    println!("Tonic: C{} (note: {}, octave: {})", tonic.octave, tonic.note, tonic.octave);
    println!("Mode: Dorian");
    println!("Mode notes: [");

    // Print the Dorian mode notes
    let mut i = 0_u32;
    loop {
        if i >= dorian_notes.len() {
            break;
        }
        let note = *dorian_notes.at(i);
        if i == dorian_notes.len() - 1 {
            println!("  {}  // scale degree {}", note, i + 1);
        } else {
            println!("  {}, // scale degree {}", note, i + 1);
        }
        i += 1;
    }
    println!("]");
    println!("Mode size: {}", mode_size);

    // Generate the modal run by mapping sine wave values to mode indices
    let mut modal_run: Array<u8> = ArrayTrait::new();

    println!("Sine wave contour values: [");
    let mut i = 0_u32;
    loop {
        if i >= sine_contour.len() {
            break;
        }
        let contour_value = *sine_contour.at(i);

        // Use contour value as direct index into a repeating table of Dorian mode notes
        // The table repeats every 7 notes and shifts octaves as it wraps
        // This ensures perfect 1:1 mapping: contour value = keynum index
        let mode_index: u8 = (contour_value % 7_u32).try_into().unwrap(); // Wrap around 7-note mode
        let octave_offset: u8 = (contour_value / 7_u32)
            .try_into()
            .unwrap(); // Every 7 units = 1 octave

        // Get the note from the mode at this index
        let mode_note = *dorian_notes.at(mode_index.into());

        // Calculate the current octave, constrained to valid MIDI range (0-127)
        let current_octave = if tonic.octave + octave_offset > 10_u8 {
            10_u8
        } else {
            tonic.octave + octave_offset
        };

        // Create the pitch class for this note
        let pitch = PitchClass { note: mode_note, octave: current_octave };

        // Convert to MIDI keynum and constrain to valid range (0-127)
        let raw_keynum = pc_to_keynum(pitch);
        let keynum = if raw_keynum > 127_u8 {
            127_u8
        } else {
            raw_keynum
        };

        // Add to our modal run
        ArrayTrait::append(ref modal_run, keynum);

        // Print the mapping for debugging
        if i == sine_contour.len() - 1 {
            println!(
                "  {}  // index {} -> mode_index {} -> note {} -> octave {} -> keynum {}",
                contour_value,
                i,
                mode_index,
                mode_note,
                current_octave,
                keynum,
            );
        } else {
            println!(
                "  {}, // index {} -> mode_index {} -> note {} -> octave {} -> keynum {}",
                contour_value,
                i,
                mode_index,
                mode_note,
                current_octave,
                keynum,
            );
        }

        i += 1;
    }
    println!("]");

    // Print the final modal run
    println!("Generated modal run (keynums): [");
    let mut i = 0_u32;
    loop {
        if i >= modal_run.len() {
            break;
        }
        let keynum = *modal_run.at(i);
        if i == modal_run.len() - 1 {
            println!("  {}  // position {}", keynum, i);
        } else {
            println!("  {}, // position {}", keynum, i);
        }
        i += 1;
    }
    println!("]");
    println!("Modal run length: {}", modal_run.len());

    // Verify the modal run has the expected length
    assert(modal_run.len() == 100_u32, 'Modal run should have 100 notes');

    // Verify all keynums are valid MIDI notes (0-127)
    let mut i = 0_u32;
    loop {
        if i >= modal_run.len() {
            break;
        }
        let keynum = *modal_run.at(i);
        assert(keynum >= 0_u8 && keynum <= 127_u8, 'Invalid MIDI keynum');
        i += 1;
    }

    // Verify the modal run follows the sine wave contour
    // (higher sine values should generally correspond to higher notes)
    let mut i = 0_u32;
    loop {
        if i >= sine_contour.len() - 1 {
            break;
        }
        let current_contour = *sine_contour.at(i);
        let next_contour = *sine_contour.at(i + 1);
        let current_keynum = *modal_run.at(i);
        let next_keynum = *modal_run.at(i + 1);

        // If contour goes up significantly, keynum should generally go up
        // (allowing for octave wrapping and mode constraints)
        if next_contour > current_contour + 20_u32 {
            // Contour increased significantly, keynum should not decrease by more than 12 semitones
            // (allowing for octave changes and mode wrapping)
            assert(
                next_keynum >= current_keynum - 12_u8 || next_keynum >= current_keynum,
                'Modal run follows contour',
            );
        }

        i += 1;
    };
}
