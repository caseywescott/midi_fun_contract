use koji::midi::modes::{
    dark_mode_at, dark_mode_count, has_minor_third, is_dark_mode, mode_steps,
};
use koji::midi::types::Modes;

fn assert_steps(actual: Span<u8>, expected: Span<u8>) {
    assert(actual.len() == expected.len(), 'mode step count');
    let mut i = 0;
    loop {
        if i >= expected.len() {
            break;
        }
        assert(*actual.at(i) == *expected.at(i), 'mode step mismatch');
        i += 1;
    };
}

#[test]
fn melodic_minor_mode_steps() {
    assert_steps(mode_steps(Modes::MelodicMinor(())), array![2_u8, 1, 2, 2, 2, 2, 1].span());
    assert_steps(mode_steps(Modes::DorianFlat2(())), array![1_u8, 2, 2, 2, 2, 1, 2].span());
    assert_steps(mode_steps(Modes::LydianAugmented(())), array![2_u8, 2, 2, 2, 1, 2, 1].span());
    assert_steps(mode_steps(Modes::LydianDominant(())), array![2_u8, 2, 2, 1, 2, 1, 2].span());
    assert_steps(mode_steps(Modes::MixolydianFlat13(())), array![2_u8, 2, 1, 2, 1, 2, 2].span());
    assert_steps(mode_steps(Modes::LocrianNatural2(())), array![2_u8, 1, 2, 1, 2, 2, 2].span());
    assert_steps(mode_steps(Modes::Altered(())), array![1_u8, 2, 1, 2, 2, 2, 2].span());
}

#[test]
fn melodic_minor_modes_span_one_octave() {
    let modes = array![
        Modes::MelodicMinor(()),
        Modes::DorianFlat2(()),
        Modes::LydianAugmented(()),
        Modes::LydianDominant(()),
        Modes::MixolydianFlat13(()),
        Modes::LocrianNatural2(()),
        Modes::Altered(()),
    ];
    let mut mode_index = 0;
    loop {
        if mode_index >= modes.len() {
            break;
        }
        let steps = mode_steps(*modes.at(mode_index));
        let mut total = 0_u8;
        let mut step_index = 0;
        loop {
            if step_index >= steps.len() {
                break;
            }
            total += *steps.at(step_index);
            step_index += 1;
        }
        assert(total == 12, 'mode must span octave');
        mode_index += 1;
    };
}

#[test]
fn harmonic_major_mode_steps() {
    assert_steps(mode_steps(Modes::HarmonicMajor(())), array![2_u8, 2, 1, 2, 1, 3, 1].span());
    assert_steps(mode_steps(Modes::DorianFlat5(())), array![2_u8, 1, 2, 1, 3, 1, 2].span());
    assert_steps(mode_steps(Modes::PhrygianFlat4(())), array![1_u8, 2, 1, 3, 1, 2, 2].span());
    assert_steps(mode_steps(Modes::LydianFlat3(())), array![2_u8, 1, 3, 1, 2, 2, 1].span());
    assert_steps(mode_steps(Modes::MixolydianFlat2(())), array![1_u8, 3, 1, 2, 2, 1, 2].span());
    assert_steps(
        mode_steps(Modes::LydianAugmentedSharp2(())), array![3_u8, 1, 2, 2, 1, 2, 1].span(),
    );
    assert_steps(
        mode_steps(Modes::LocrianDoubleFlat7(())), array![1_u8, 2, 2, 1, 2, 1, 3].span(),
    );
}

#[test]
fn additional_dark_and_symmetric_mode_steps() {
    assert_steps(mode_steps(Modes::DorianSharp4(())), array![2_u8, 1, 3, 1, 2, 1, 2].span());
    assert_steps(mode_steps(Modes::LocrianNatural6(())), array![1_u8, 2, 2, 1, 3, 1, 2].span());
    assert_steps(mode_steps(Modes::WholeTone(())), array![2_u8, 2, 2, 2, 2, 2].span());
    assert_steps(
        mode_steps(Modes::HalfWholeDiminished(())), array![1_u8, 2, 1, 2, 1, 2, 1, 2].span(),
    );
    assert_steps(
        mode_steps(Modes::WholeHalfDiminished(())), array![2_u8, 1, 2, 1, 2, 1, 2, 1].span(),
    );
}

#[test]
fn dark_mode_designation() {
    assert(dark_mode_count() == 11, 'dark mode count');
    let mut i = 0;
    loop {
        if i >= dark_mode_count() {
            break;
        }
        let mode = dark_mode_at(i);
        assert(is_dark_mode(mode), 'dark mode designated');
        assert(has_minor_third(mode), 'dark mode minor third');
        i += 1;
    };
    assert(!is_dark_mode(Modes::WholeTone(())), 'whole tone not dark');
    assert(!has_minor_third(Modes::WholeTone(())), 'whole tone no minor third');
    assert(has_minor_third(Modes::Altered(())), 'altered contains minor third');
    assert(!is_dark_mode(Modes::Altered(())), 'altered not curated dark');
}
