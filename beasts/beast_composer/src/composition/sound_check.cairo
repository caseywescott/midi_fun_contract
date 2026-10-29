//! The Sound Check: a Beast's scale through each of its presets, byte-identical to the lab's
//! `soundCheckMidi` (offchain/beast-sound/src/lab.js). Each preset gets a block of ten quarter
//! notes:
//! four quarters on the Beast's scale (a pattern picked by the Beast), a held note, four staccato
//! blips an octave up; the drum kit closes it. The presets are the Beast's family (three leads,
//! three plucks) and the two mega leads when shiny, from a start picked by the Beast. The key is
//! the Beast's own: its special name's, or its species' spread key without one, in the mode's real
//! scale. One per Beast from its species, special name and shiny flag.

use core::poseidon::poseidon_hash_span;
use crate::composition::beast_score::BeastForm;
use crate::composition::beast_v3_sound::{PackableBeastV3, map_v3_beast_to_composition_params};
use crate::composition::full_midi::{
    Arrangement, MEGA_LEADS, beast_form_to_full_smf_bytes_arranged, family_leads, family_plucks,
};
use crate::composition::genesis::{genesis_mode, named_mode_scale, neutral_live};
use crate::composition::melodic_canon::NoteEvent;

const BLOCK: u32 = 4800;
const KIT_VOICE: u32 = 9;

fn name_variant(prefix: u8, suffix: u8) -> u32 {
    if prefix == 0 {
        0
    } else {
        1 + (prefix.into() - 1) * 18 + (suffix.into() - 1)
    }
}

pub fn sound_check_smf_bytes(beast: PackableBeastV3) -> Array<u8> {
    let named = beast.prefix != 0;
    let g = PackableBeastV3 {
        prefix: 0, suffix: 0, level: 50, health: 200, shiny: 0, animated: 0, ..beast,
    };
    let key_beast = if named {
        PackableBeastV3 { prefix: beast.prefix, suffix: beast.suffix, ..g }
    } else {
        PackableBeastV3 {
            prefix: ((beast.id - 1) % 69 + 1).try_into().unwrap(),
            suffix: ((beast.id - 1) % 18 + 1).try_into().unwrap(),
            ..g,
        }
    };
    let kp = map_v3_beast_to_composition_params(key_beast, neutral_live());
    let mode = if named {
        kp.mode_id
    } else {
        genesis_mode(beast.id, kp.mode_id)
    };
    let scale = match named_mode_scale(mode) {
        Option::Some(s) => s,
        Option::None => array![0, 2, 3, 5, 7, 8, 10].span(),
    };
    let tonic: u32 = kp.tonic_keynum.into();
    let nv = name_variant(beast.prefix, beast.suffix);
    let hash: u256 = poseidon_hash_span(
        array!['BEAST_SOUND_CHECK', beast.id.into(), nv.into()].span(),
    )
        .into();
    let h: u32 = (hash % 0x100000000).try_into().unwrap();

    let leads = family_leads(beast.beast_type).span();
    let plucks = family_plucks(beast.beast_type).span();
    let mut presets: Array<u8> = array![
        *leads.at(0), *leads.at(1), *leads.at(2), *plucks.at(0), *plucks.at(1), *plucks.at(2),
    ];
    if beast.shiny == 1 {
        presets.append(*MEGA_LEADS.span().at(0));
        presets.append(*MEGA_LEADS.span().at(1));
    }
    let n = presets.len();
    let rot = h % n;
    let pattern: Span<i32> = match (h / 0x100) % 4 {
        0 => array![0, 1, 2, 3].span(),
        1 => array![0, 2, 4, 7].span(),
        2 => array![7, 4, 2, 0].span(),
        _ => array![0, 2, 1, 3].span(),
    };
    let held: i32 = if (h / 0x1000) % 2 == 1 {
        4
    } else {
        7
    };
    let blips: Span<i32> = array![7, 9, 11, 14].span();

    let mut events: Array<NoteEvent> = array![];
    let mut programs: Array<u8> = array![];
    let mut v: u32 = 0;
    while v < n {
        let t0 = v * BLOCK;
        programs.append(*presets.at((v + rot) % n));
        let mut k: u32 = 0;
        for d in pattern {
            events.append(note(t0 + k * 480, 420, pitch(tonic, scale, *d), 100, v));
            k += 1;
        }
        events.append(note(t0 + 1920, 1380, pitch(tonic, scale, held), 96, v));
        let mut k: u32 = 0;
        for d in blips {
            events.append(note(t0 + 3360 + k * 240, 60, pitch(tonic, scale, *d), 90, v));
            k += 1;
        }
        v += 1;
    }
    while programs.len() <= KIT_VOICE {
        programs.append(0);
    }
    let k0 = n * BLOCK;
    let kit: Span<u8> = array![36, 38, 42, 46, 49, 50, 47, 45].span();
    let mut k: u32 = 0;
    for key in kit {
        events.append(note(k0 + k * 480, 240, *key, 100, KIT_VOICE));
        k += 1;
    }
    let length = k0 + BLOCK;
    let form = BeastForm { events, score_hash: 0, section_count: 1, length_ticks: length };
    beast_form_to_full_smf_bytes_arranged(
        @form,
        500000,
        beast.tier,
        Option::None,
        false,
        0,
        Arrangement {
            top_lead: false,
            balanced: false,
            drums: false,
            rock: false,
            extra: Option::None,
            programs: Option::Some(programs.span()),
        },
    )
}

fn pitch(tonic: u32, scale: Span<u8>, d: i32) -> u8 {
    let d: u32 = d.try_into().unwrap();
    let off: u32 = (*scale.at(d % 7)).into();
    (tonic + 12 * (d / 7) + off).try_into().unwrap()
}

fn note(time: u32, duration: u32, pitch: u8, velocity: u8, voice_id: u32) -> NoteEvent {
    NoteEvent { time, duration, pitch, velocity, voice_id }
}


/// Explicit scale/preset recipe. Musical performance is already resolved by the
/// caller and no temporal context/hash exists on the Sound Check path.
pub fn sound_check_from_inputs(
    x: beast_composer_inputs::SoundCheckInputs, mega: bool,
) -> Array<u8> {
    beast_composer_inputs::validate_inputs(beast_composer_inputs::ComposerInputs::SoundCheck(x));
    let scale = named_mode_scale(x.mode_id).unwrap();
    let tonic: u32 = x.tonic_keynum.into();
    let hash: u256 = poseidon_hash_span(
        array![
            'BEAST_SOUND_CHECK', x.identity.source_species_id.into(),
            x.identity.name_variant_id.into(),
        ]
            .span(),
    )
        .into();
    let h: u32 = (hash % 0x100000000).try_into().unwrap();
    let leads = family_leads(x.family).span();
    let plucks = family_plucks(x.family).span();
    let mut presets: Array<u8> = array![
        *leads.at(0), *leads.at(1), *leads.at(2), *plucks.at(0), *plucks.at(1), *plucks.at(2),
    ];
    if mega {
        presets.append(*MEGA_LEADS.span().at(0));
        presets.append(*MEGA_LEADS.span().at(1));
    }
    let n = presets.len();
    let rot = h % n;
    let pattern: Span<i32> = match (h / 0x100) % 4 {
        0 => array![0, 1, 2, 3].span(),
        1 => array![0, 2, 4, 7].span(),
        2 => array![7, 4, 2, 0].span(),
        _ => array![0, 2, 1, 3].span(),
    };
    let held: i32 = if (h / 0x1000) % 2 == 1 {
        4
    } else {
        7
    };
    let blips: Span<i32> = array![7, 9, 11, 14].span();

    let mut events: Array<NoteEvent> = array![];
    let mut programs: Array<u8> = array![];
    let mut v: u32 = 0;
    while v < n {
        let t0 = v * BLOCK;
        programs.append(*presets.at((v + rot) % n));
        let mut k: u32 = 0;
        for d in pattern {
            events.append(note(t0 + k * 480, 420, pitch(tonic, scale, *d), 100, v));
            k += 1;
        }
        events.append(note(t0 + 1920, 1380, pitch(tonic, scale, held), 96, v));
        let mut k: u32 = 0;
        for d in blips {
            events.append(note(t0 + 3360 + k * 240, 60, pitch(tonic, scale, *d), 90, v));
            k += 1;
        }
        v += 1;
    }
    while programs.len() <= KIT_VOICE {
        programs.append(0);
    }
    let k0 = n * BLOCK;
    let kit: Span<u8> = array![36, 38, 42, 46, 49, 50, 47, 45].span();
    let mut k: u32 = 0;
    for key in kit {
        events.append(note(k0 + k * 480, 240, *key, 100, KIT_VOICE));
        k += 1;
    }
    let length = k0 + BLOCK;
    let mut performed = array![];
    for e in events.span() {
        let e = *e;
        let duration = if x.articulation_profile == 1 {
            {
                let n = e.duration / 2;
                if n > 60 {
                    n
                } else {
                    60
                }
            }
        } else if x.articulation_profile == 5 {
            {
                let n = e.duration * 3 / 4;
                if n > 60 {
                    n
                } else {
                    60
                }
            }
        } else {
            e.duration
        };
        let velocity: u32 = e.velocity.into()
            + if x.articulation_profile == 3 && e.time % 1920 == 0 {
                8
            } else {
                0
            };
        let velocity = if velocity > x.velocity_ceiling.into() {
            x.velocity_ceiling
        } else {
            velocity.try_into().unwrap()
        };
        performed.append(NoteEvent { duration, velocity, ..e });
    }
    let form = BeastForm {
        events: performed, score_hash: 0, section_count: 1, length_ticks: length,
    };
    beast_form_to_full_smf_bytes_arranged(
        @form,
        x.tempo_us,
        5, // No generated groove/fills: the explicit kit audition is already in the form.
        Option::None,
        false,
        0,
        Arrangement {
            top_lead: false,
            balanced: false,
            drums: false,
            rock: false,
            extra: Option::None,
            programs: Option::Some(programs.span()),
        },
    )
}
