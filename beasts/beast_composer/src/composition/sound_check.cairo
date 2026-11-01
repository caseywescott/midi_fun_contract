//! Curated single-voice species warmups: distinct contours, rhythms, held notes and short gates.
//! Data is generated from the JS audition catalogue by scripts/check_catalogue.mjs.
use midi::smf::{TrackWriter, TrackWriterTrait, smf_bytes};
use crate::composition::beast_v11::articulated_duration;
use crate::composition::beast_v3_sound::{PackableBeastV3, map_v3_beast_to_composition_params};
use crate::composition::check_catalogue_data::catalogue_check;
use crate::composition::cyclops_sound_check::cyclops_sound_check_tracks;
use crate::composition::genesis::{genesis_mode, genesis_swap, named_mode_scale, neutral_live};
use crate::inputs::{MusicIdentity, SoundCheckInputs, validate_sound_check};
use crate::opaque::opaque;

pub fn sound_check_smf_bytes(beast: PackableBeastV3) -> Array<u8> {
    sound_check_from_inputs(sound_check_inputs(beast), beast.shiny == 1)
}

/// Name0 uses the actual shared Song's palette; names keep their established named key.
/// Sound Check identity and preset remain the original species even when its Song is swapped.
pub fn sound_check_inputs(beast: PackableBeastV3) -> SoundCheckInputs {
    let named = beast.prefix != 0;
    let source = if named {
        beast.id
    } else {
        genesis_swap(beast.id)
    };
    let g = PackableBeastV3 {
        id: source, prefix: 0, suffix: 0, level: 50, health: 200, shiny: 0, animated: 0, ..beast,
    };
    let key_beast = if named {
        PackableBeastV3 { prefix: beast.prefix, suffix: beast.suffix, ..g }
    } else {
        PackableBeastV3 {
            prefix: ((source - 1) % 69 + 1).try_into().unwrap(),
            suffix: ((source - 1) % 18 + 1).try_into().unwrap(),
            ..g,
        }
    };
    let kp = map_v3_beast_to_composition_params(key_beast, neutral_live());
    let (meta, _, _) = catalogue_check(beast.id.try_into().unwrap(), beast.beast_type);
    SoundCheckInputs {
        identity: MusicIdentity {
            source_species_id: beast.id.try_into().unwrap(),
            name_variant_id: if named {
                (1 + (beast.prefix.into() - 1) * 18 + (beast.suffix.into() - 1)).try_into().unwrap()
            } else {
                0
            },
        },
        mode_id: if beast.id == 44 && (!named || (beast.prefix == 1 && beast.suffix == 1)) {
            7
        } else if named {
            kp.mode_id
        } else {
            genesis_mode(source, kp.mode_id)
        },
        tonic_keynum: if beast.id == 44 && (!named || (beast.prefix == 1 && beast.suffix == 1)) {
            57
        } else {
            kp.tonic_keynum
        },
        family: beast.beast_type,
        tempo_us: if beast.id == 64 {
            342857
        } else {
            (meta / 0x8000000000).try_into().unwrap()
        },
        velocity_ceiling: 100,
        articulation_profile: 0,
    }
}

/// Perform a written candidate on its stable species preset (mega retains the song's lead parity).
/// Cyclops retains its eight-timbre sequence and follows the same performance values.
pub fn sound_check_from_inputs(x: SoundCheckInputs, mega: bool) -> Array<u8> {
    smf_bytes(1, 480, sound_check_tracks(x, mega).span())
}

/// Track bodies shared by the byte-file and packed pure-composer entrypoints.
pub fn sound_check_tracks(x: SoundCheckInputs, mega: bool) -> Array<Array<u8>> {
    validate_sound_check(x);
    if x.identity.source_species_id == 64 {
        return cyclops_sound_check_tracks(x);
    }
    let scale = named_mode_scale(x.mode_id).unwrap();
    let (meta, mut head, mut response) = catalogue_check(x.identity.source_species_id, x.family);
    let program: u8 = if mega {
        if (meta / 128) % 2 == 1 {
            65
        } else {
            50
        }
    } else {
        (meta % 128).try_into().unwrap()
    };
    let tonic: u32 = if (meta / 256) % 2 == 1 {
        48
    } else {
        60
    } + (x.tonic_keynum % 12).into();
    let rhythm = (meta / 512) % 0x10000;
    let held = (meta / 0x2000000) % 256;
    let count: u32 = ((meta / 0x200000000) % 32).try_into().unwrap();
    let pan = (meta / 0x4000000000) % 2 == 1;
    let mut tempo = TrackWriterTrait::new();
    tempo.tempo(0, x.tempo_us);
    let mut track = TrackWriterTrait::new();
    track.program(0, 0, program);
    track.control(0, 0, 7, 100);
    track.control(0, 0, 10, if pan {
        48
    } else {
        64
    });
    let expression = BoxTrait::new((tonic, scale, x.articulation_profile, x.velocity_ceiling));
    let original_head = head;
    let mut time = 0;
    // Four two-bar sections: head, two held tones, answering phrase, articulation with a final
    // rest.
    let mut section: u32 = opaque(0);
    while section < 4 {
        if section == 1 {
            let mut h = held;
            let mut k: u32 = 0;
            while k < 2 {
                write_note(
                    ref track, time, 1800, ((h % 16) + 4).try_into().unwrap(), 100, expression,
                );
                time += 1920;
                h /= 16;
                k += 1;
            }
        } else {
            let mut degrees = if section == 0 {
                head
            } else if section == 2 {
                response
            } else {
                original_head
            };
            let mut durations = rhythm;
            let n = if section == 3 {
                count
            } else {
                16
            };
            let mut k: u32 = 0;
            while k < n {
                let short = section == 3;
                // Final four tones are the head's curated cadence, even for shorter articulation
                // sections.
                if short && k == count - 4 {
                    degrees = original_head / 0x1000000000000;
                }
                let slot: u32 = if short {
                    240
                } else {
                    ((durations % 16) * 120).try_into().unwrap()
                };
                write_note(
                    ref track,
                    time,
                    if short {
                        40
                    } else {
                        slot * 5 / 6
                    },
                    (degrees % 16).try_into().unwrap(),
                    if short {
                        100
                    } else {
                        96
                    },
                    expression,
                );
                time += slot;
                degrees /= 16;
                durations /= 16;
                if k % 4 == 3 {
                    durations = rhythm;
                }
                k += 1;
            }
        }
        if section == 1 {
            track.control(time, 0, 10, if pan {
                80
            } else {
                64
            });
        }
        if section == 2 {
            track.control(time, 0, 10, 64);
        }
        section += 1;
    }
    array![tempo.finish_at(15360), track.finish_at(15360)]
}

/// Five-bit effective degree -4..11 represented as a nibble +4; avoid negative pitch arithmetic.
#[inline(never)]
fn write_note(
    ref track: TrackWriter,
    time: u32,
    duration: u32,
    encoded: u32,
    velocity: u8,
    expression: Box<(u32, Span<u8>, u8, u8)>,
) {
    let (tonic, scale, articulation_profile, velocity_ceiling) = expression.unbox();
    let d = encoded + 3;
    let pitch: u8 = (tonic + (d / 7) * 12 + (*scale.at(d % 7)).into() - 12).try_into().unwrap();
    let short = articulated_duration(duration, articulation_profile);
    let gate = if short < duration {
        short
    } else {
        duration
    };
    let velocity: u32 = velocity.into()
        + if articulation_profile == 3 && time % 1920 == 0 {
            8
        } else {
            0
        };
    let velocity: u8 = if velocity > velocity_ceiling.into() {
        velocity_ceiling
    } else {
        velocity.try_into().unwrap()
    };
    track.note_on(time, 0, pitch, velocity);
    track.note_off(time + gate, 0, pitch, 0);
}
