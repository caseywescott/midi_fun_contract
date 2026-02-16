use koji::geom_series::{
    arith_array_diff_fill_waves, arith_array_fill, geom_array_diff_fill, geom_array_diff_fill_waves,
};

/// Test geom_array_diff_fill function
/// This test verifies that the geometric series with differentiation function:
/// - Generates the correct number of values
/// - Produces both series and diff arrays
/// - Prints the output for inspection
#[test]
fn test_geom_array_diff_fill() {
    // Test parameters: arr_size=20, grow_rate=5, initval=2
    let arr_size: felt252 = 20;
    let grow_rate: felt252 = 5;
    let initval: felt252 = 2;

    // Generate the geometric series with differentiation
    let (series, diff) = geom_array_diff_fill(arr_size, grow_rate, initval);

    // Print the series array
    println!("GEOMETRIC SERIES WITH DIFFERENTIATION:");
    println!("Parameters: arr_size={}, grow_rate={}, initval={}", arr_size, grow_rate, initval);
    println!("Series array: [");

    let mut i: usize = 0;
    loop {
        if i >= series.len() {
            break;
        }
        let value = *series.at(i);
        if i == series.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Series array length: {}", series.len());

    // Print the diff array
    println!("Diff array (growth rates): [");
    let mut i: usize = 0;
    loop {
        if i >= diff.len() {
            break;
        }
        let value = *diff.at(i);
        if i == diff.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Diff array length: {}", diff.len());

    // Assertions
    let series_len: felt252 = series.len().into();
    let diff_len: felt252 = diff.len().into();
    assert(series_len == 20, 'Series should have 20');
    assert(diff_len == 20, 'Diff should have 20');
    assert(series_len == diff_len, 'Same length');
}

/// Test geom_array_diff_fill with different parameters
#[test]
fn test_geom_array_diff_fill_different_params() {
    // Test parameters: arr_size=5, grow_rate=2, initval=10
    let arr_size: felt252 = 5;
    let grow_rate: felt252 = 2;
    let initval: felt252 = 10;

    // Generate the geometric series with differentiation
    let (series, diff) = geom_array_diff_fill(arr_size, grow_rate, initval);

    // Print the series array
    println!("GEOMETRIC SERIES WITH DIFFERENTIATION (Different Parameters):");
    println!("Parameters: arr_size={}, grow_rate={}, initval={}", arr_size, grow_rate, initval);
    println!("Series array: [");

    let mut i: usize = 0;
    loop {
        if i >= series.len() {
            break;
        }
        let value = *series.at(i);
        if i == series.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Series array length: {}", series.len());

    // Print the diff array
    println!("Diff array (growth rates): [");
    let mut i: usize = 0;
    loop {
        if i >= diff.len() {
            break;
        }
        let value = *diff.at(i);
        if i == diff.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Diff array length: {}", diff.len());

    // Assertions
    assert(series.len() == 5, 'Series should have 5 elements');
    assert(diff.len() == 5, 'Diff should have 5 elements');
}

/// Test geom_array_diff_fill_waves function
/// This test verifies that the wave function creates oscillating patterns
#[test]
fn test_geom_array_diff_fill_waves() {
    // Test parameters: arr_size=5, grow_rate=1, initval=0, cycles=2
    let arr_size: felt252 = 5;
    let grow_rate: felt252 = 1;
    let initval: felt252 = 0;
    let cycles: felt252 = 2;

    // Generate the wave pattern
    let (wave_series, wave_diff) = geom_array_diff_fill_waves(arr_size, grow_rate, initval, cycles);

    // Print the wave series array
    println!("GEOMETRIC SERIES WITH WAVES:");
    println!(
        "Parameters: arr_size={}, grow_rate={}, initval={}, cycles={}",
        arr_size,
        grow_rate,
        initval,
        cycles,
    );
    println!("Wave series array: [");

    let mut i: usize = 0;
    loop {
        if i >= wave_series.len() {
            break;
        }
        let value = *wave_series.at(i);
        if i == wave_series.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Wave series array length: {}", wave_series.len());

    // Print the wave diff array
    println!("Wave diff array (growth rates): [");
    let mut i: usize = 0;
    loop {
        if i >= wave_diff.len() {
            break;
        }
        let value = *wave_diff.at(i);
        if i == wave_diff.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Wave diff array length: {}", wave_diff.len());

    // Assertions
    // Base array has 5 elements, each cycle adds 10 (5 original + 5 reversed)
    // So cycles=2 should give us 20 elements total
    let expected_len: felt252 = (arr_size * cycles * 2).into();
    let series_len: felt252 = wave_series.len().into();
    let diff_len: felt252 = wave_diff.len().into();
    assert(series_len == expected_len, 'Wave series length');
    assert(diff_len == expected_len, 'Wave diff length');
    assert(series_len == diff_len, 'Same length');
}

/// Test arith_array_fill function
/// This test verifies that the arithmetic series function:
/// - Generates the correct number of values
/// - Uses constant step size
/// - Prints the output for inspection
#[test]
fn test_arith_array_fill() {
    // Test parameters: size=10, start=0, step=1
    let size: felt252 = 10;
    let start: felt252 = 0;
    let step: felt252 = 1;

    // Generate the arithmetic series
    let result = arith_array_fill(size, start, step);

    // Print the array
    println!("ARITHMETIC SERIES:");
    println!("Parameters: size={}, start={}, step={}", size, start, step);
    println!("Array: [");

    let mut i: usize = 0;
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

    // Assertions
    let result_len: felt252 = result.len().into();
    assert(result_len == 10, 'Array should have 10');

    // Verify first value is start
    assert(*result.at(0) == start, 'First value should be start');

    // Verify step is constant
    if result.len() > 1 {
        let first_step = *result.at(1) - *result.at(0);
        assert(first_step == step, 'Step should be constant');
    }
}

/// Test arith_array_fill with different parameters
#[test]
fn test_arith_array_fill_different_params() {
    // Test parameters: size=8, start=10, step=3
    let size: felt252 = 8;
    let start: felt252 = 10;
    let step: felt252 = 3;

    // Generate the arithmetic series
    let result = arith_array_fill(size, start, step);

    // Print the array
    println!("ARITHMETIC SERIES (Different Parameters):");
    println!("Parameters: size={}, start={}, step={}", size, start, step);
    println!("Array: [");

    let mut i: usize = 0;
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

    // Assertions
    let result_len: felt252 = result.len().into();
    assert(result_len == 8, 'Array should have 8');
    assert(*result.at(0) == start, 'First value should be start');

    // Verify the sequence: 10, 13, 16, 19, 22, 25, 28, 31
    assert(*result.at(0) == 10, 'Value at index 0');
    assert(*result.at(1) == 13, 'Value at index 1');
    assert(*result.at(7) == 31, 'Value at index 7');
}

/// Test arith_array_diff_fill_waves function
/// This test verifies that the arithmetic wave function creates oscillating patterns
#[test]
fn test_arith_array_diff_fill_waves() {
    // Test parameters: size=5, start=0, step=2, cycles=2
    let size: felt252 = 5;
    let start: felt252 = 0;
    let step: felt252 = 2;
    let cycles: felt252 = 2;

    // Generate the wave pattern
    let (wave_series, wave_diff) = arith_array_diff_fill_waves(size, start, step, cycles);

    // Print the wave series array
    println!("ARITHMETIC SERIES WITH WAVES:");
    println!("Parameters: size={}, start={}, step={}, cycles={}", size, start, step, cycles);
    println!("Wave series array: [");

    let mut i: usize = 0;
    loop {
        if i >= wave_series.len() {
            break;
        }
        let value = *wave_series.at(i);
        if i == wave_series.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Wave series array length: {}", wave_series.len());

    // Print the wave diff array
    println!("Wave diff array (step values): [");
    let mut i: usize = 0;
    loop {
        if i >= wave_diff.len() {
            break;
        }
        let value = *wave_diff.at(i);
        if i == wave_diff.len() - 1 {
            println!("  {}  // index {}", value, i);
        } else {
            println!("  {}, // index {}", value, i);
        }
        i += 1;
    }
    println!("]");
    println!("Wave diff array length: {}", wave_diff.len());

    // Assertions
    // Base array has 5 elements, each cycle adds 10 (5 original + 5 reversed)
    // So cycles=2 should give us 20 elements total
    let expected_len: felt252 = (size * cycles * 2).into();
    let series_len: felt252 = wave_series.len().into();
    let diff_len: felt252 = wave_diff.len().into();
    assert(series_len == expected_len, 'Wave series length');
    assert(diff_len == expected_len, 'Wave diff length');
    assert(series_len == diff_len, 'Same length');

    // Verify the wave pattern: [0, 2, 4, 6, 8, 8, 6, 4, 2, 0, 0, 2, 4, 6, 8, 8, 6, 4, 2, 0]
    assert(*wave_series.at(0) == 0, 'First value');
    assert(*wave_series.at(4) == 8, 'Peak of first wave');
    assert(*wave_series.at(5) == 8, 'Start of reverse');
    assert(*wave_series.at(9) == 0, 'End of first cycle');
}

