//! Beast sound MIDI proofs.
//!
//! Export one demo at a time:
//!   ./scripts/generate_midi_from_test.sh beast_tier5_low_history_midi_test demos/beasts/01_tier5_low_history.mid

use koji::composition::beast_score::{
    beast_form_to_midi, build_beast_form_from_traits, build_beast_ornamented_midi,
    get_composition_params,
};
use koji::composition::beast_trait_map::{
    VISUAL_ANIMATED, VISUAL_COMMON, VISUAL_SHINY, BeastLiveStats,
};
use koji::midi::output::output_midi_object;
use koji::midi::types::{Message, Midi, NoteOff, NoteOn, SetTempo};

fn low_history() -> BeastLiveStats {
    BeastLiveStats {
        level: 1,
        health: 10,
        adventurers_defeated: 0,
        times_defeated: 0,
        encounter_count: 0,
        species_rank: 1243,
        is_crown: false,
    }
}

fn high_crown() -> BeastLiveStats {
    BeastLiveStats {
        level: 128,
        health: 999,
        adventurers_defeated: 64,
        times_defeated: 8,
        encounter_count: 32,
        species_rank: 1,
        is_crown: true,
    }
}

fn scarred() -> BeastLiveStats {
    BeastLiveStats {
        level: 16,
        health: 80,
        adventurers_defeated: 3,
        times_defeated: 8,
        encounter_count: 12,
        species_rank: 25,
        is_crown: false,
    }
}

fn high_kills() -> BeastLiveStats {
    BeastLiveStats {
        level: 64,
        health: 180,
        adventurers_defeated: 64,
        times_defeated: 1,
        encounter_count: 80,
        species_rank: 5,
        is_crown: false,
    }
}

fn build_demo_midi(
    species_id: u8, name_variant_id: u32, visual: u8, seed: felt252, stats: BeastLiveStats,
) -> Midi {
    let form = build_beast_form_from_traits(species_id, name_variant_id, visual, seed, stats);
    beast_form_to_midi(@form, 500000)
}

fn assert_valid_demo_midi(midiobj: @Midi, min_note_ons: u32) {
    let mut ev = midiobj.clone().events;
    let mut note_on_count: u32 = 0;
    loop {
        match ev.pop_front() {
            Option::Some(msg) => {
                match msg {
                    Message::NOTE_ON(_) => {
                        note_on_count += 1;
                    },
                    _ => {},
                }
            },
            Option::None(_) => {
                break;
            },
        }
    }
    assert(note_on_count >= min_note_ons, 'note on count');
    let binary = output_midi_object(midiobj);
    assert(binary.len() >= 22, 'MIDI too short');
}

fn generate_parser_format(midiobj: @Midi) {
    let mut ev = midiobj.clone().events;
    loop {
        match ev.pop_front() {
            Option::Some(currentevent) => {
                match currentevent {
                    Message::NOTE_ON(NoteOn) => {
                        println!(
                            "Message::NOTE_ON(NoteOn {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                            *NoteOn.channel,
                            *NoteOn.note,
                            *NoteOn.velocity,
                            *NoteOn.time,
                        );
                    },
                    Message::NOTE_OFF(NoteOff) => {
                        println!(
                            "Message::NOTE_OFF(NoteOff {{ channel: {}, note: {}, velocity: {}, time: {} }})",
                            *NoteOff.channel,
                            *NoteOff.note,
                            *NoteOff.velocity,
                            *NoteOff.time,
                        );
                    },
                    Message::SET_TEMPO(SetTempo) => {
                        match *SetTempo.time {
                            Option::Some(time_val) => {
                                println!(
                                    "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::Some({}) }})",
                                    *SetTempo.tempo,
                                    time_val,
                                );
                            },
                            Option::None(_) => {
                                println!(
                                    "Message::SET_TEMPO(SetTempo {{ tempo: {}, time: Option::None }})",
                                    *SetTempo.tempo,
                                );
                            },
                        };
                    },
                    _ => {},
                }
            },
            Option::None(_) => {
                break;
            },
        }
    }
}

#[ignore]
#[test]
fn beast_tier5_low_history_midi_test() {
    let midi = build_demo_midi(74, 0, VISUAL_COMMON, 10101, low_history());
    assert_valid_demo_midi(@midi, 12);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_tier5_high_crown_midi_test() {
    let midi = build_demo_midi(74, 1242, VISUAL_ANIMATED, 10102, high_crown());
    assert_valid_demo_midi(@midi, 60);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_tier3_scarred_midi_test() {
    let midi = build_demo_midi(30, 19, VISUAL_COMMON, 10103, scarred());
    assert_valid_demo_midi(@midi, 40);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_tier3_high_kills_midi_test() {
    let midi = build_demo_midi(30, 400, VISUAL_SHINY, 10104, high_kills());
    assert_valid_demo_midi(@midi, 80);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_tier1_bare_dragon_midi_test() {
    let midi = build_demo_midi(0, 0, VISUAL_COMMON, 10105, low_history());
    assert_valid_demo_midi(@midi, 16);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_tier1_crown_midi_test() {
    let midi = build_demo_midi(0, 1242, VISUAL_ANIMATED, 10106, high_crown());
    assert_valid_demo_midi(@midi, 120);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_magic_weakness_midi_test() {
    let midi = build_demo_midi(2, 36, VISUAL_SHINY, 10107, high_kills());
    assert_valid_demo_midi(@midi, 80);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_bludgeon_weakness_midi_test() {
    let midi = build_demo_midi(1, 54, VISUAL_COMMON, 10108, high_kills());
    assert_valid_demo_midi(@midi, 80);
    generate_parser_format(@midi);
}

// --- 3-voice ornamented canon path ---

fn build_ornamented_3v_midi(
    species_id: u8, name_variant_id: u32, visual: u8, seed: felt252, stats: BeastLiveStats,
) -> Midi {
    let params = get_composition_params(species_id, name_variant_id, visual, seed, stats);
    build_beast_ornamented_midi(params, seed)
}

#[ignore]
#[test]
fn beast_3v_orn_tier5_low_midi_test() {
    let midi = build_ornamented_3v_midi(74, 0, VISUAL_COMMON, 20101, low_history());
    assert_valid_demo_midi(@midi, 12);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_3v_orn_tier5_crown_midi_test() {
    let midi = build_ornamented_3v_midi(74, 1242, VISUAL_ANIMATED, 20102, high_crown());
    assert_valid_demo_midi(@midi, 60);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_3v_orn_tier3_scarred_midi_test() {
    let midi = build_ornamented_3v_midi(30, 19, VISUAL_COMMON, 20103, scarred());
    assert_valid_demo_midi(@midi, 40);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_3v_orn_tier3_high_kills_midi_test() {
    let midi = build_ornamented_3v_midi(30, 400, VISUAL_SHINY, 20104, high_kills());
    assert_valid_demo_midi(@midi, 80);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_3v_orn_tier1_bare_dragon_midi_test() {
    let midi = build_ornamented_3v_midi(0, 0, VISUAL_COMMON, 20105, low_history());
    assert_valid_demo_midi(@midi, 16);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_3v_orn_tier1_crown_midi_test() {
    let midi = build_ornamented_3v_midi(0, 1242, VISUAL_ANIMATED, 20106, high_crown());
    assert_valid_demo_midi(@midi, 120);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_3v_orn_magic_weakness_midi_test() {
    let midi = build_ornamented_3v_midi(2, 36, VISUAL_SHINY, 20107, high_kills());
    assert_valid_demo_midi(@midi, 80);
    generate_parser_format(@midi);
}

#[ignore]
#[test]
fn beast_3v_orn_bludgeon_weakness_midi_test() {
    let midi = build_ornamented_3v_midi(1, 54, VISUAL_COMMON, 20108, high_kills());
    assert_valid_demo_midi(@midi, 80);
    generate_parser_format(@midi);
}
