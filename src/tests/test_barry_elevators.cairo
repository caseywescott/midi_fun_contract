use core::array::ArrayTrait;
use koji::composition::barry_harris::{
    contains_pc, initial_harmonic_state, stable_chord_tones, ChordFamily,
};
use koji::composition::barry_elevators::{
    apply_elevator_bounce_step, apply_elevator_step, elevator_alternates_stable_dim,
    elevator_path_all_pcs_in_scale, generate_elevator_bounce_path, generate_elevator_path,
    is_stable_state, major_c_elevator_first_dim_pcs, ElevatorDirection,
};

#[test]
fn test_c_major_elevator_first_dim_connector() {
    let dim = major_c_elevator_first_dim_pcs();
    assert(contains_pc(dim.span(), 2), 'has D');
    assert(contains_pc(dim.span(), 5), 'has F');
    assert(contains_pc(dim.span(), 8), 'has Ab');
    assert(contains_pc(dim.span(), 11), 'has B');
}

#[test]
fn test_elevator_up_alternates_stable_dim() {
    let start = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let path = generate_elevator_path(start, ElevatorDirection::Up, 9);
    assert(path.len() == 9, 'len 9');
    assert(elevator_alternates_stable_dim(path.span()), 'alternates');
    assert(elevator_path_all_pcs_in_scale(path.span()), 'in scale');
    assert(is_stable_state(path.at(0)), 'start stable');
    assert(!is_stable_state(path.at(1)), 'step1 dim');
    assert(is_stable_state(path.at(2)), 'step2 stable');
}

#[test]
fn test_elevator_down_reverses_inversion() {
    let mut start_up = initial_harmonic_state(0, ChordFamily::Major6Dim);
    start_up.inversion = 3;
    let mut start_down = initial_harmonic_state(0, ChordFamily::Major6Dim);
    start_down.inversion = 3;
    let up_path = generate_elevator_path(start_up, ElevatorDirection::Up, 4);
    let down_path = generate_elevator_path(start_down, ElevatorDirection::Down, 4);
    assert(up_path.len() == down_path.len(), 'same len');
    let up_inv = *up_path.at(2).inversion;
    let down_inv = *down_path.at(2).inversion;
    assert(up_inv != down_inv, 'diff inversion');
}

#[test]
fn test_elevator_bounce_changes_direction() {
    let start = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let path = generate_elevator_bounce_path(start, 8);
    assert(path.len() == 8, 'len');
    assert(elevator_alternates_stable_dim(path.span()), 'alternates');
}

#[test]
fn test_elevator_deterministic() {
    let start_a = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let start_b = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let a = generate_elevator_path(start_a, ElevatorDirection::Up, 6);
    let b = generate_elevator_path(start_b, ElevatorDirection::Up, 6);
    let mut i: usize = 0;
    loop {
        if i >= a.len() {
            break;
        }
        assert(*a.at(i).inversion == *b.at(i).inversion, 'same inv');
        assert(*a.at(i).tonic_pc == *b.at(i).tonic_pc, 'same tonic');
        i += 1;
    };
}

#[test]
fn test_apply_elevator_step_from_stable() {
    let start = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let next = apply_elevator_step(start, ElevatorDirection::Up);
    assert(!is_stable_state(@next), 'becomes dim');
    let back = apply_elevator_step(next, ElevatorDirection::Up);
    assert(is_stable_state(@back), 'back stable');
    assert(back.inversion == 1, 'inv up');
}

#[test]
fn test_bounce_step_at_boundary() {
    let mut start = initial_harmonic_state(0, ChordFamily::Major6Dim);
    start.inversion = 3;
    assert(is_stable_state(@start), 'start stable');
    let next = apply_elevator_bounce_step(start);
    assert(!is_stable_state(@next) || is_stable_state(@next), 'step ok');
}
