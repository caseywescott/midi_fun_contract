use core::array::ArrayTrait;
use koji::composition::barry_harris::ChordFamily;
use koji::composition::barry_labyrinth::BarryTurnaroundKind;
use koji::composition::barry_turnarounds::{
    barry_turnaround_to_timeline, generate_barry_turnaround, six_to_two_five_function_labels,
    turnaround_starts_and_ends_on_tonic, turnaround_total_duration,
};

#[test]
fn test_turnaround_starts_ends_tonic() {
    assert(
        turnaround_starts_and_ends_on_tonic(0, BarryTurnaroundKind::SixToTwoFive, 16), '625',
    );
    assert(
        turnaround_starts_and_ends_on_tonic(0, BarryTurnaroundKind::BackdoorSixDim, 12), 'backdoor',
    );
}

#[test]
fn test_turnaround_bounded_duration() {
    let steps = generate_barry_turnaround(0, BarryTurnaroundKind::OneSixTwoFive, 16);
    let total = turnaround_total_duration(steps.span());
    assert(total <= 16, 'bounded');
}

#[test]
fn test_turnaround_nonempty_pcs() {
    let timeline = barry_turnaround_to_timeline(0, BarryTurnaroundKind::SixToTwoFive, 16);
    assert(timeline.targets.len() > 0, 'targets');
}

#[test]
fn test_six_to_two_five_functions() {
    let labels = six_to_two_five_function_labels();
    assert(labels.len() == 5, 'five steps');
    assert(*labels.at(0) == 1, 'I');
    assert(*labels.at(1) == 6, 'VI');
    assert(*labels.at(2) == 2, 'ii');
    assert(*labels.at(3) == 5, 'V');
    assert(*labels.at(4) == 1, 'I end');
}

#[test]
fn test_turnaround_small_length_no_underflow() {
    // Regression: tiny length_steps must not underflow u8 durations.
    let mut len: u8 = 1;
    loop {
        if len > 4 {
            break;
        }
        let a = generate_barry_turnaround(0, BarryTurnaroundKind::SixToTwoFive, len);
        assert(a.len() == 5, '625 steps');
        let b = generate_barry_turnaround(0, BarryTurnaroundKind::TritoneDominantChain, len);
        assert(b.len() == 4, 'tritone steps');
        let c = generate_barry_turnaround(0, BarryTurnaroundKind::DiminishedPassingTurnaround, len);
        assert(c.len() == 5, 'dim steps');
        let d = generate_barry_turnaround(0, BarryTurnaroundKind::BackdoorSixDim, len);
        assert(d.len() == 4, 'backdoor steps');
        assert(
            turnaround_starts_and_ends_on_tonic(0, BarryTurnaroundKind::SixToTwoFive, len),
            'starts ends',
        );
        len += 1;
    };
}

#[test]
fn test_turnaround_deterministic() {
    let a = generate_barry_turnaround(0, BarryTurnaroundKind::TritoneDominantChain, 12);
    let b = generate_barry_turnaround(0, BarryTurnaroundKind::TritoneDominantChain, 12);
    assert(a.len() == b.len(), 'same len');
    assert(*a.at(0).tonic_pc == *b.at(0).tonic_pc, 'same tonic');
}
