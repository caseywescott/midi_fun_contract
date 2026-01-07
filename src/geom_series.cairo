use core::array::ArrayTrait;

//*****************************************************************************************************
// Sequencable Collections
//*****************************************************************************************************

/// Create Geometric Series
/// Useful for musical Accelerandos/Deccelerandos (speeding-up/slowing down)
///
/// Fills an array with a geometric series where each value grows by an increasing rate.
/// The grow_rate itself increases by 1 each iteration.
pub fn geom_array_fill(arr_size: felt252, grow_rate: felt252, initval: felt252) -> Array<felt252> {
    let mut result = ArrayTrait::new();

    if arr_size == 0 {
        return result;
    }

    let mut current_val = initval + grow_rate;
    let mut current_grow_rate = grow_rate;
    let mut remaining = arr_size;

    loop {
        if remaining == 0 {
            break ();
        }

        result.append(current_val);
        current_grow_rate = current_grow_rate + 1;
        current_val = current_val + current_grow_rate;
        remaining = remaining - 1;
    }

    result
}

/// Create Geometric Series and differentiate values
/// Useful for creating notes for Accelerandos/Deccelerandos that play until the next note
///
/// Returns a tuple of (series_array, diff_array) where diff_array contains the growth rates.
pub fn geom_array_diff_fill(
    arr_size: felt252, grow_rate: felt252, initval: felt252,
) -> (Array<felt252>, Array<felt252>) {
    let mut series = ArrayTrait::new();
    let mut diff = ArrayTrait::new();

    if arr_size == 0 {
        return (series, diff);
    }

    let mut current_val = initval + grow_rate;
    let mut current_grow_rate = grow_rate;
    let mut remaining = arr_size;

    loop {
        if remaining == 0 {
            break ();
        }

        series.append(current_val);
        diff.append(current_grow_rate);
        current_grow_rate = current_grow_rate + 1;
        current_val = current_val + current_grow_rate;
        remaining = remaining - 1;
    }

    (series, diff)
}

/// Create Array of arr_size with initval incremented by inc each step
/// Useful for creating a base pulse/rhythm/Pedal-Point etc
pub fn array_fill(arr_size: felt252, inc: felt252, initval: felt252) -> Array<felt252> {
    let mut result = ArrayTrait::new();

    if arr_size == 0 {
        return result;
    }

    let mut current_val = initval + inc;
    let mut current_inc = inc;
    let mut remaining = arr_size;

    loop {
        if remaining == 0 {
            break ();
        }

        result.append(current_val);
        current_inc = current_inc + 1;
        current_val = current_val + current_inc;
        remaining = remaining - 1;
    }

    result
}

/// Copy one array to another
pub fn copy_array(arr: @Array<felt252>) -> Array<felt252> {
    let mut result = ArrayTrait::new();
    let mut span = arr.span();

    loop {
        match span.pop_front() {
            Option::Some(value) => { result.append(*value); },
            Option::None => { break; },
        };
    }

    result
}

/// Append one array to another
/// Useful for creating note Scores
pub fn append_arr(arr1: @Array<felt252>, arr2: @Array<felt252>) -> Array<felt252> {
    let mut result = ArrayTrait::new();

    // First, copy arr1
    let mut span1 = arr1.span();
    loop {
        match span1.pop_front() {
            Option::Some(value) => { result.append(*value); },
            Option::None => { break; },
        };
    }

    // Then, append arr2
    let mut span2 = arr2.span();
    loop {
        match span2.pop_front() {
            Option::Some(value) => { result.append(*value); },
            Option::None => { break; },
        };
    }

    result
}

/// Retrograde set operation
/// Useful for melodic/rhythmic variation
/// Returns a new array with elements in reverse order
pub fn reverse_arr(arr: @Array<felt252>) -> Array<felt252> {
    let mut result = ArrayTrait::new();
    let arr_len = arr.len();

    if arr_len == 0 {
        return result;
    }

    let mut idx: usize = 0;
    loop {
        if idx == arr_len {
            break ();
        }

        let reverse_idx = arr_len - 1 - idx;
        match arr.get(reverse_idx) {
            Option::Some(value) => { result.append(*value.unbox()); },
            Option::None => {},
        }

        idx += 1;
    }

    result
}

/// Remove all occurrences of an item from an array
pub fn remove_item_from_array(arr: @Array<felt252>, item: felt252) -> Array<felt252> {
    let mut result = ArrayTrait::new();
    let mut span = arr.span();

    loop {
        match span.pop_front() {
            Option::Some(value) => { if *value != item {
                result.append(*value);
            } },
            Option::None => { break; },
        };
    }

    result
}
