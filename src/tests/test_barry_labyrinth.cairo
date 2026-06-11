use koji::composition::barry_harris::{ChordFamily, generate_barry_phrase};
use koji::composition::barry_labyrinth::{
    barry_labyrinth_plan_from_seed, barry_labyrinth_v2_lcg_from_seed, generate_barry_labyrinth_phrase,
    BarryLimitation, BarryTextureMode, BARRY_LABYRINTH_V2_PLAN_ID, BARRY_LABYRINTH_V2_TAG,
};
use koji::composition::barry_profiles::BarryRuleProfile;
use koji::lcg::LCG;

#[test]
fn test_labyrinth_plan_deterministic() {
    let seed: felt252 = 0xB200_0000_0000_1234;
    let p1 = barry_labyrinth_plan_from_seed(seed);
    let p2 = barry_labyrinth_plan_from_seed(seed);
    assert(p1.texture_mode == p2.texture_mode, 'texture');
    assert(p1.limitation == p2.limitation, 'limitation');
    assert(p1.max_line_cell_len == p2.max_line_cell_len, 'line len');
    assert(p1.version_id == BARRY_LABYRINTH_V2_PLAN_ID, 'version');
}

#[test]
fn test_labyrinth_v2_lcg_from_seed() {
    let seed: felt252 = 0xB200_0000_0000_0042;
    let lcg = barry_labyrinth_v2_lcg_from_seed(seed);
    assert(lcg.state != 0, 'lcg nonzero');
}

#[test]
fn test_labyrinth_phrase_bounded_output() {
    let seed: felt252 = 0xB200_0000_0000_ABCD;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 16, BarryRuleProfile::BebopLine, 48, 72,
    );
    assert(phrase.base_phrase.states.len() == 16, 'states');
    assert(phrase.base_phrase.voicings.len() == 16, 'voicings');
    assert(phrase.note_events.len() > 0, 'notes');
    assert(phrase.plan.version_id == BARRY_LABYRINTH_V2_PLAN_ID, 'plan id');
}

#[test]
fn test_labyrinth_same_seed_same_phrase() {
    let seed: felt252 = 0xB200_0000_0000_7777;
    let a = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 8, BarryRuleProfile::Conservative, 48, 72,
    );
    let b = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 8, BarryRuleProfile::Conservative, 48, 72,
    );
    assert(a.plan.texture_mode == b.plan.texture_mode, 'texture');
    assert(a.note_events.len() == b.note_events.len(), 'events');
}

#[test]
fn test_v1_phrase_unchanged_by_v2_module() {
    let seed: felt252 = 42;
    let v1a = generate_barry_phrase(
        seed, 0, ChordFamily::Major6Dim, 8, BarryRuleProfile::BebopLine, 48, 72,
    );
    let v1b = generate_barry_phrase(
        seed, 0, ChordFamily::Major6Dim, 8, BarryRuleProfile::BebopLine, 48, 72,
    );
    assert(v1a.states.len() == v1b.states.len(), 'v1 states');
    assert(v1a.voicings.len() == v1b.voicings.len(), 'v1 voicings');
}
