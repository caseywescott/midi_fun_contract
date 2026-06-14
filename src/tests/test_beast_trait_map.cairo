use koji::composition::beast_trait_map::{
    BEAST_PREFIX_COUNT, REGISTER_HIGH, REGISTER_LOW, REGISTER_MID, bare_name_dark_key,
    prefix_to_dark_key,
};
use koji::midi::modes::is_dark_mode;

#[test]
fn prefix_key_cells_use_canonical_dark_modes() {
    let mut prefix_id = 0_u8;
    loop {
        if prefix_id >= BEAST_PREFIX_COUNT {
            break;
        }
        let key = prefix_to_dark_key(prefix_id);
        assert(is_dark_mode(key.mode), 'prefix mode must be dark');
        assert(key.tonic_pc < 12, 'tonic pc bound');
        assert(key.register_band <= REGISTER_HIGH, 'register bound');
        prefix_id += 1;
    };
}

#[test]
fn prefix_key_cell_calculation_is_stable() {
    let first = prefix_to_dark_key(0);
    assert(first.canonical_mode_id == 4, 'first mode Dorian');
    assert(first.tonic_pc == 0, 'first tonic C');
    assert(first.register_band == REGISTER_LOW, 'first register low');

    let last = prefix_to_dark_key(68);
    assert(last.canonical_mode_id == 5, 'last mode Phrygian');
    assert(last.tonic_pc == 8, 'last tonic Ab');
    assert(last.register_band == REGISTER_HIGH, 'last register high');
}

#[test]
fn bare_name_key_cells_are_bounded_phrygian() {
    let apex = bare_name_dark_key(8, 1);
    assert(apex.canonical_mode_id == 5, 'bare mode Phrygian');
    assert(apex.tonic_pc == 8, 'Dragon tonic Ab');
    assert(apex.register_band == REGISTER_LOW, 'apex register low');

    let dangerous = bare_name_dark_key(30, 3);
    assert(dangerous.register_band == REGISTER_MID, 'dangerous register mid');

    let common = bare_name_dark_key(74, 5);
    assert(common.register_band == REGISTER_HIGH, 'common register high');
}
