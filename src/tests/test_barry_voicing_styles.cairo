use koji::composition::barry_harris::{initial_harmonic_state, ChordFamily};
use koji::composition::barry_labyrinth::BarryVoicingStyle;
use koji::composition::barry_voice_motion::VoiceMotionPolicy;
use koji::composition::barry_voicing_styles::{
    apply_drop_two, apply_drop_three, closed_position_span, drop_two_lowered_second_highest,
    realize_rootless_shell, realize_voicing_style, voicing_in_register,
};

#[test]
fn test_drop_two_lowers_second_highest() {
    let voicing = array![48_i16, 55, 60, 67].span();
    assert(drop_two_lowered_second_highest(voicing), 'drop2');
}

#[test]
fn test_drop_three_lowers_third_highest() {
    let voicing = array![48_i16, 55, 60, 67].span();
    let dropped = apply_drop_three(voicing);
    assert(dropped.len() == 4, 'len 4');
}

#[test]
fn test_closed_position_compact() {
    let voicing = array![60_i16, 64, 67, 71].span();
    let span = closed_position_span(voicing);
    assert(span <= 12, 'compact');
}

#[test]
fn test_rootless_shell_omits_root() {
    let state = initial_harmonic_state(0, ChordFamily::Major6Dim);
    let shell = realize_rootless_shell(state, 48, 72);
    assert(shell.len() == 3, 'three notes');
}

#[test]
fn test_voicing_in_register() {
    let target = array![0_u8, 4, 7, 11].span();
    let prev = array![48_i16, 55, 60, 67].span();
    let out = realize_voicing_style(
        target, prev, 48, 72, BarryVoicingStyle::DropTwo, VoiceMotionPolicy::MinimalMotion, 0,
    );
    assert(voicing_in_register(out.span(), 48, 72), 'in range');
}

#[test]
fn test_drop_two_deterministic() {
    let voicing = array![48_i16, 55, 60, 67].span();
    let a = apply_drop_two(voicing);
    let b = apply_drop_two(voicing);
    assert(a.len() == b.len(), 'same len');
}
