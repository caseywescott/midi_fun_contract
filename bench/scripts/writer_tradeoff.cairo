use beast_composer::inputs::ComposerInputs;
use beast_composer::composition::genesis::genesis_song_inputs;
use beast_composer::composition::sound_check::sound_check_inputs;
use beast_contracts::pure_composer::{IBeastPureComposerDispatcher, IBeastPureComposerDispatcherTrait};
use midi::interfaces::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};
use crate::cases;

// FROZEN_ARRAYS

fn inputs(kind: u8, sid: u64, ceiling: u8) -> ComposerInputs {
    let mut b = cases::gbeast(sid, 0);
    if kind == 2 { b.prefix = 1; b.suffix = 1; }
    if kind == 0 || kind == 3 {
        let mut check = sound_check_inputs(b);
        if kind == 3 {
            check.articulation_profile = 1;
            check.velocity_ceiling = ceiling;
            check.tempo_us = if ceiling == 1 { 1 } else { 1048575 };
        }
        ComposerInputs::SoundCheck(check)
    } else {
        ComposerInputs::Song(genesis_song_inputs(b, b.prefix, b.suffix, 0, Option::None))
    }
}

#[inline(never)]
fn pure(case: u32, kind: u8, sid: u64, fx: u8, ceiling: u8) {
    let x = fixed_inputs(case, kind, sid, ceiling);
    let addr = cases::deploy("BeastPureComposer", array![]);
    let sound = IBeastPureComposerDispatcher { contract_address: addr }.compose(x, fx);
    let mut input = array![]; Serde::serialize(@x, ref input);
    let mut out = array![]; Serde::serialize(@sound, ref out);
    verify(case, input, out);
}

#[inline(never)]
fn legacy(case: u32, sid: u64, shiny: u8) {
    let w = cases::world();
    let b = cases::gbeast(sid, shiny);
    let l = cases::live(0, 0, 1, 954);
    let token = cases::set_state(w, b, l);
    let result = IMidiProviderDispatcher { contract_address: w.provider }.get_midi(token);
    let mut input = array![]; Serde::serialize(@b, ref input); Serde::serialize(@l, ref input);
    let mut out = array![]; Serde::serialize(@result, ref out);
    verify(case, input, out);
}

#[inline(never)]
fn scale(case: u32, token: u256) {
    let addr = cases::deploy("ScaleMidiProvider", array!['BEASTS']);
    let result = IMidiProviderDispatcher { contract_address: addr }.get_midi(token);
    let mut input = array![]; Serde::serialize(@token, ref input);
    let mut out = array![]; Serde::serialize(@result, ref out);
    verify(case, input, out);
}

#[cfg(feature: 'record')]
fn verify(case: u32, input: Array<felt252>, out: Array<felt252>) {
    println!("WRITER case={} input={:?} out={:?}", case, input, out);
}
#[cfg(not(feature: 'record'))]
fn verify(case: u32, input: Array<felt252>, out: Array<felt252>) {
    let (expected_input, expected_out) = frozen(case);
    assert(input == expected_input, 'writer input changed');
    assert(out == expected_out, 'writer full output changed');
}

// CASE_TESTS

#[cfg(feature: 'record')]
fn fixed_inputs(case: u32, kind: u8, sid: u64, ceiling: u8) -> ComposerInputs {
    inputs(kind, sid, ceiling)
}
#[cfg(not(feature: 'record'))]
fn fixed_inputs(case: u32, kind: u8, sid: u64, ceiling: u8) -> ComposerInputs {
    let (input, _) = frozen(case);
    let mut span = input.span();
    let value: ComposerInputs = Serde::deserialize(ref span).expect('frozen input invalid');
    assert(span.is_empty(), 'frozen input tail');
    value
}
