//! Beast Sound end to end: BeastMidiProvider's get_settings (Serde) and get_midi bytes through the
//! declared class, as the Beasts NFT would call it. `build` is the fixture baseline.
use onchain_midi_player::interface::IOnchainTinySynthDispatcherTrait;
use onchain_midi_player::settings::validate;
use crate::beast_e2e_fixtures::{
    HEAVIEST_LEN, WARLOCK_LEN, beast_mega_settings, beast_settings, heaviest_midi, warlock_midi,
};
use crate::helpers::{beasts_token_uri, class};

#[test]
fn beast_build() {
    let s = beast_settings();
    assert(s.timbres.len() == 12, 'timbres');
    assert(warlock_midi().len() == WARLOCK_LEN, 'warlock');
    assert(heaviest_midi().len() == HEAVIEST_LEN, 'heaviest');
}

#[test]
fn beast_settings_validate() {
    validate(@beast_settings());
    validate(@beast_mega_settings());
}

#[test]
fn beast_lc_midi_segment_warlock() {
    let seg = class().midi_segment(warlock_midi(), beast_settings());
    assert(seg.len() > WARLOCK_LEN, 'segment');
}

#[test]
fn beast_lc_midi_segment_heaviest() {
    let seg = class().midi_segment(heaviest_midi(), beast_mega_settings());
    assert(seg.len() > HEAVIEST_LEN, 'segment');
}

#[test]
fn beast_token_uri_heaviest() {
    let uri = beasts_token_uri(
        @"\"name\":\"Beast\"", @"<svg xmlns='http://www.w3.org/2000/svg'/>", heaviest_midi(),
        @beast_mega_settings(),
    );
    assert(uri.len() > 0, 'uri');
}

#[test]
#[ignore]
fn beast_token_uri_warlock_print() {
    let uri = beasts_token_uri(
        @"\"name\":\"Warlock\"", @"<svg xmlns='http://www.w3.org/2000/svg'/>", warlock_midi(),
        @beast_settings(),
    );
    println!("URI {}", uri);
}

#[test]
fn beast_lc_midi_segment_heaviest_default_settings() {
    let seg = class()
        .midi_segment(heaviest_midi(), onchain_midi_player::settings::default_settings());
    assert(seg.len() > HEAVIEST_LEN, 'segment');
}

#[test]
fn beast_direct_midi_segment_heaviest() {
    let seg = onchain_midi_player::segment::midi_segment(heaviest_midi(), @beast_mega_settings());
    assert(seg.len() > HEAVIEST_LEN, 'segment');
}

#[test]
fn beast_encode_settings() {
    let e = onchain_midi_player::settings::encode(@beast_settings());
    assert(e.len() > 0, 'encode');
}
