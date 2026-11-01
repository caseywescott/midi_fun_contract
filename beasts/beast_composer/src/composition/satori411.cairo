//! Explicit authored Satori recipe from the original Sound Check lab's track 411.
//! Reserved dual felt markers opt in without reinterpreting ordinary stored Satori inputs.
use midi::smf::{TrackWriter, TrackWriterTrait};
use crate::composition::beast_score::BeastForm;
use crate::composition::beast_v11::{articulated_duration, shape};
use crate::composition::full_midi::{
    Arrangement, Voicing, beast_form_to_full_tracks_arranged, mega_lead_pick, note_on_off,
};
use crate::composition::melodic_canon::NoteEvent;
use crate::inputs::{
    ArrangementInputs, ChannelPolicy, MusicIdentity, ScoreInputs, SongInputs, SpecialArrangement,
    ThemeInputs, TreatmentInputs,
};
use crate::opaque::opaque;

pub const THEME_MARKER: felt252 = 'SATORI_LAB_411_V1';
pub const RHYTHM_MARKER: felt252 = 'SATORI_FORM_36_V1';
const END: u32 = 69120;

pub fn is_satori411(x: SongInputs) -> bool {
    marked(x.arrangement.identity.source_species_id, x.theme.motif_seed, x.treatment.rhythm_seed)
}

#[inline(never)]
fn marked(species: u32, theme: felt252, rhythm: felt252) -> bool {
    species == 44 && theme == THEME_MARKER && rhythm == RHYTHM_MARKER
}

/// Explicitly select the authored score. Existing recipes without both markers keep their music.
pub fn from_base(base: SongInputs, name: u16) -> SongInputs {
    let mut x = SongInputs {
        theme: ThemeInputs { motif_seed: THEME_MARKER, tier: 4, register_band: 2 },
        score: ScoreInputs {
            mode_id: 7,
            tonic_keynum: 57,
            tier: 4,
            weakness: 1,
            voice_count: 3,
            section_count: 1,
            stretto_lag: 1,
            use_inversion: false,
            use_countersubject: false,
            ornament_density: 0,
            articulation_profile: 0,
            velocity_ceiling: 127,
            tempo_us: 500000,
        },
        treatment: TreatmentInputs {
            rhythm_seed: RHYTHM_MARKER,
            flip_side: false,
            development: 0,
            direction: 0,
            spacing: 1,
            trill: false,
            prominence: 0,
            section_rhythm: false,
        },
        arrangement: ArrangementInputs {
            family: 1,
            identity: MusicIdentity { source_species_id: 44, name_variant_id: name },
            channel_count: 4,
            channel_policy: ChannelPolicy::Genesis,
            special: SpecialArrangement::None,
            top_lead: true,
            balanced: false,
            weak_ties: true,
        },
    };
    if name == 1 {
        // Casey's named controls on the same species motif, not a new theme seed.
        // The procedural theme keeps its species register; the named register is encoded
        // by Casey's mapped tonic48/60/72 plus pitch class. Select that authored treatment.
        x
            .theme
            .register_band =
                if base.score.tonic_keynum < 60 {
                    0
                } else if base.score.tonic_keynum < 72 {
                    1
                } else {
                    2
                };
        x.score.mode_id = base.score.mode_id;
        x.score.tonic_keynum = base.score.tonic_keynum;
        x.score.ornament_density = base.score.ornament_density;
        x.treatment.trill = base.treatment.trill;
    }
    x
}

/// Future edition-zero purchases retain the authored form, varied in key and tempo by their seed.
/// Historical purchases retain their snapshotted unmarked base.
pub fn purchased(mut x: SongInputs, seed: felt252) -> SongInputs {
    let n: u256 = seed.into();
    let named = x.theme.register_band == 0;
    if !named {
        x.score.tonic_keynum = (55 + n % 5).try_into().unwrap();
    }
    let rate = if named {
        n % 5
    } else {
        n / 5 % 5
    };
    x.score.tempo_us = (480000 + rate * 10000).try_into().unwrap();
    x.arrangement.channel_policy = ChannelPolicy::Seeded(seed);
    x
}

#[inline(never)]
fn setup(channel: u8, program: u8, pan: u8) -> TrackWriter {
    let mut t = TrackWriterTrait::new();
    if channel != 9 {
        t.program(0, channel, program);
    }
    t.control(0, channel, 7, 100);
    t.control(0, channel, 10, pan);
    t
}

#[inline(never)]
fn note(
    ref t: TrackWriter,
    channel: u8,
    time: u32,
    key: u8,
    duration: u32,
    velocity: u8,
    expression: (u8, u8),
) {
    let (profile, ceiling) = expression;
    // Authored gates100..920 share Casey's exact duration rule (portato never hits its floor).
    let duration = articulated_duration(duration, profile);
    let velocity = if velocity > ceiling {
        ceiling
    } else {
        velocity
    };
    // Use the same exact on/off encoder as the general full-MIDI arranger.
    note_on_off(ref t, channel, time, duration, key, velocity);
}

/// One authored score; effect arrangement and reference serialization consume the same notes.
fn events(x: SongInputs) -> Array<NoteEvent> {
    let named = x.theme.register_band == 0;
    let (mut role, mut out): (u32, Array<NoteEvent>) = opaque((0, array![]));
    while role < 3 {
        let mut bar: u32 = opaque(0);
        while bar < 36 {
            let at = bar * 1920;
            let (root, a, b, c): (u8, u8, u8, u8) = match bar % 4 {
                0 => (45, 57, 60, 64),
                1 => (41, 53, 57, 60),
                2 => (36, 48, 52, 55),
                _ => (43, 55, 59, 62),
            };
            let rest = bar >= 24 && bar < 28;
            let count: u32 = if role == 1 {
                8
            } else if role == 2 && bar >= 1 {
                16
            } else if role == 0 && bar >= 4 && !rest {
                4
            } else {
                0
            };
            let mut i: u32 = opaque(0);
            while i < count {
                let (offset, key, duration, velocity): (u32, u8, u32, u8) = if role == 1 {
                    (i * 240, root + if i % 4 == 2 {
                        7
                    } else {
                        0
                    }, 200, 100)
                } else if role == 2 {
                    (
                        i * 120,
                        match i % 3 {
                            0 => a,
                            1 => b,
                            _ => c,
                        } + if i % 6 > 2 {
                            24
                        } else {
                            12
                        },
                        100,
                        70,
                    )
                } else {
                    match i {
                        0 => (0, b + 24, if named {
                            680
                        } else {
                            920
                        }, 100),
                        1 => (
                            if named {
                                720
                            } else {
                                960
                            },
                            c + 24,
                            if named {
                                680
                            } else {
                                440
                            },
                            100,
                        ),
                        2 => (1440, b + 24, 220, 100),
                        _ => (1680, a + 24, 220, 100),
                    }
                };
                out
                    .append(
                        NoteEvent {
                            time: at + offset,
                            pitch: key + x.score.tonic_keynum - 57,
                            duration,
                            velocity,
                            voice_id: role,
                        },
                    );
                i += 1;
            }
            bar += 1;
        }
        role += 1;
    }
    out
}

#[inline(never)]
fn original_drums(ceiling: u8, reference: bool) -> Array<u8> {
    let (mut bar, mut writer): (u32, TrackWriter) = opaque(
        (0, if reference {
            setup(9, 0, 64)
        } else {
            TrackWriterTrait::with_running_status()
        }),
    );
    while bar < 36 {
        let at = bar * 1920;
        let rest = bar >= 24 && bar < 28;
        if bar >= 8 {
            let mut i: u32 = opaque(0);
            while i < 8 {
                writer
                    .note_on(
                        at + i * 240, 9, 42, capped(if i % 2 == 1 {
                            50
                        } else {
                            76
                        }, ceiling),
                    );
                if !rest {
                    if i == 0 || i == 4 {
                        writer.note_on(at + i * 240, 9, 36, capped(110, ceiling));
                    }
                    if i == 2 || i == 6 {
                        writer.note_on(at + i * 240, 9, 38, capped(100, ceiling));
                    }
                }
                if bar == 16 && i == 0 {
                    writer.note_on(at, 9, 49, capped(100, ceiling));
                }
                i += 1;
            }
        }
        if bar == 0 {
            writer.note_on(0, 9, 49, capped(100, ceiling));
        }
        bar += 1;
    }
    writer.finish_at(END)
}

/// Normal written playback preserves original411's MIDI encoding and channel mix exactly.
/// Effects reuse Casey's v1.1 dynamics and full MIDI mega/echo arranger, not a palette exemption.
#[inline(never)]
pub fn tracks(x: SongInputs, mega: bool, echo: bool) -> Array<Array<u8>> {
    let mut notes = events(x);
    if mega || echo {
        shape(
            ref notes,
            x.score.velocity_ceiling,
            x.score.articulation_profile,
            END,
            x.treatment.prominence.into(),
        );
        let form = BeastForm { events: notes, score_hash: 0, section_count: 1, length_ticks: END };
        let mut out = beast_form_to_full_tracks_arranged(
            @form,
            x.score.tempo_us,
            x.score.tier,
            Option::Some(
                Voicing {
                    beast_type: 1,
                    species_id: 44,
                    name_variant_id: x.arrangement.identity.name_variant_id.into(),
                    voice_count: 3,
                    use_countersubject: false,
                },
            ),
            mega,
            mega_lead_pick(44, x.arrangement.identity.name_variant_id.into()),
            Arrangement {
                top_lead: false,
                balanced: false,
                drums: mega,
                rock: false,
                extra: Option::None,
                programs: Option::Some(array![0, 15, 17].span()),
                echo,
                grace: 0,
                grace_all: false,
                fill: 0,
                tonic: 0,
                scale: [].span(),
            },
        );
        if !mega {
            out.append(original_drums(x.score.velocity_ceiling, false));
        }
        return out;
    }
    let mut tempo = TrackWriterTrait::new();
    tempo.tempo(0, x.score.tempo_us);
    let (mut role, mut out): (u32, Array<Array<u8>>) = opaque((0, array![tempo.finish_at(END)]));
    while role < 3 {
        let (program, pan): (u8, u8) = match role {
            0 => (0, 50),
            1 => (15, 40),
            _ => (17, 80),
        };
        let mut writer = setup(role.try_into().unwrap(), program, pan);
        for e in notes.span() {
            if e.voice_id == role {
                note(
                    ref writer,
                    role.try_into().unwrap(),
                    e.time,
                    e.pitch,
                    e.duration,
                    e.velocity,
                    (x.score.articulation_profile, x.score.velocity_ceiling),
                );
            }
        }
        out.append(writer.finish_at(END));
        role += 1;
    }
    out.append(original_drums(x.score.velocity_ceiling, true));
    out
}

#[inline(never)]
fn capped(velocity: u8, ceiling: u8) -> u8 {
    if velocity > ceiling {
        ceiling
    } else {
        velocity
    }
}

#[cfg(test)]
mod tests {
    use core::poseidon::poseidon_hash_span;
    use midi::smf::{TrackWriterTrait, smf_bytes};
    use crate::composition::beast_v3_sound::PackableBeastV3;
    use crate::composition::drift::Drift;
    use crate::composition::genesis::{beast_song_inputs, drifted_song_inputs, purchase_song_inputs};
    use crate::inputs::{ComposerInputs, decode_inputs, encode_inputs};
    use super::{RHYTHM_MARKER, THEME_MARKER, is_satori411, note, tracks};

    fn beast() -> PackableBeastV3 {
        PackableBeastV3 {
            id: 44,
            prefix: 0,
            suffix: 0,
            level: 50,
            health: 200,
            shiny: 0,
            animated: 0,
            tier: 4,
            beast_type: 1,
        }
    }

    #[test]
    fn test_satori411_staccato_floor_matches_casey_song_performance() {
        let mut writer = TrackWriterTrait::new();
        note(ref writer, 0, 0, 60, 100, 100, (1, 127));
        assert(
            writer.finish() == array![0, 144, 60, 100, 60, 128, 60, 64, 0, 255, 47, 0],
            '60tick minimum gate',
        );
    }

    #[test]
    fn test_satori411_exact_reference_midi() {
        let x = beast_song_inputs(beast(), 0, 0);
        assert(is_satori411(x), 'authored base');
        let midi = smf_bytes(1, 480, tracks(x, false, false).span());
        assert(midi.len() == 9720, 'reference length');
        let mut values = array![];
        for b in midi.span() {
            values.append((*b).into());
        }
        assert(
            poseidon_hash_span(
                values.span(),
            ) == 0x39a228c2995119595b72ef561bf06664a107d5ff150025cddc14c896fc931d,
            'reference midi',
        );
    }

    #[test]
    fn test_satori411_effects_match_independent_js_reference() {
        let expected = array![
            0x3a4739617e5f179a399de21702ade6db98d14ef1fcd7be8dad21c843ec9fb34,
            0x351e6ec341c7695175fd344912be0a9c84bfd6647f9d7dc7d52a8c6a60fdf20,
            0x3daf09a452f33f54c593905de1af3a6d6f258bb3a0a5c950b598282cb20cb7b,
            0x6cd701a2b816f766161e54e1a6320102606555d9f8394d4255bb41899202dec,
        ];
        let base = beast_song_inputs(beast(), 1, 1);
        let mut fx: u8 = 0;
        while fx < 4 {
            let performed = crate::composition::performance::apply_performance(
                ComposerInputs::Song(base), fx,
            );
            let x = match performed {
                ComposerInputs::Song(x) => x,
                _ => panic!("song expected"),
            };
            let midi = smf_bytes(1, 480, tracks(x, fx == 1 || fx == 3, fx >= 2).span());
            let mut values = array![];
            for b in midi.span() {
                values.append((*b).into());
            }
            assert(
                poseidon_hash_span(values.span()) == *expected.at(fx.into()), 'effects reference',
            );
            fx += 1;
        }
    }

    #[test]
    fn test_satori411_shared_effects_match_independent_js_reference() {
        let expected = array![
            0x39a228c2995119595b72ef561bf06664a107d5ff150025cddc14c896fc931d,
            0xa140fe708316c6749b98826fa8e1ada705788841e718e5141d271b78537a2,
            0x5d233d77f025935d685635431020fc43313b6d8dc6917f3bbf8c6d76e98c8f5,
            0x37a5e41eb09cf79931fea26874225a7372fa4e01f7662e8ee7a05dbcacdb634,
        ];
        let base = beast_song_inputs(beast(), 0, 0);
        let mut fx: u8 = 0;
        while fx < 4 {
            let performed = crate::composition::performance::apply_performance(
                ComposerInputs::Song(base), fx,
            );
            let x = match performed {
                ComposerInputs::Song(x) => x,
                _ => panic!("song expected"),
            };
            let midi = smf_bytes(1, 480, tracks(x, fx == 1 || fx == 3, fx >= 2).span());
            let mut values = array![];
            for b in midi.span() {
                values.append((*b).into());
            }
            assert(
                poseidon_hash_span(values.span()) == *expected.at(fx.into()), 'effects reference',
            );
            fx += 1;
        }
    }

    #[test]
    fn test_satori411_named_register_and_old_markers_survive_drift() {
        let shared = beast_song_inputs(beast(), 0, 0);
        let named = beast_song_inputs(beast(), 1, 1);
        let d = Drift {
            rhythm: Option::Some(123), rotate: Option::Some(0), day_knob: 0, delta_bpm: 0, day: 40,
        };
        let changed = drifted_song_inputs(named, d);
        assert(is_satori411(changed), 'drift preserves marker');
        assert(changed.theme.register_band == 0, 'named register retained');
        assert(changed.score.ornament_density == 0, 'existing weekly ornament rule');
        assert(changed.score.tonic_keynum == 55, 'existing monthly key rule');
        let shared_changed = drifted_song_inputs(shared, d);
        assert(shared_changed.theme.register_band == 2, 'shared written phrase retained');
        let mut legacy_marked = shared;
        legacy_marked.arrangement.identity.name_variant_id = 1;
        assert(
            smf_bytes(
                1, 480, tracks(legacy_marked, false, false).span(),
            ) == smf_bytes(1, 480, tracks(shared, false, false).span()),
            'old marked base unchanged',
        );
    }

    #[test]
    fn test_satori411_agony_bane_and_reserved_marker_roundtrip() {
        let x = beast_song_inputs(beast(), 1, 1);
        assert(is_satori411(x), 'name base');
        assert(x.arrangement.identity.name_variant_id == 1, 'Agony Bane');
        assert(x.score.mode_id == 7 && x.score.tonic_keynum == 48, 'Casey named C Aeolian');
        assert(x.theme.register_band == 0 && x.score.ornament_density == 1, 'Casey named profile');
        assert(!x.treatment.trill, 'Casey Bane no trill');
        let wire = encode_inputs(ComposerInputs::Song(x));
        assert(decode_inputs(wire.span()) == ComposerInputs::Song(x), 'canonical roundtrip');
        assert(
            poseidon_hash_span(
                wire.span(),
            ) == 0x22d0f7a38431fcf13f4760282e12a34717294a5e787315f5f10fbe6088f22c9,
            'JS named wire',
        );
        let mut other = x;
        other.treatment.rhythm_seed = 0;
        assert(!is_satori411(other), 'both markers needed');
        other.treatment.rhythm_seed = RHYTHM_MARKER;
        other.theme.motif_seed = 0;
        assert(!is_satori411(other), 'both markers needed');
        other.theme.motif_seed = THEME_MARKER;
        other.arrangement.identity.source_species_id = 43;
        assert(!is_satori411(other), 'species marker');
        assert(!is_satori411(beast_song_inputs(beast(), 1, 2)), 'other named base');
        let a = purchase_song_inputs(x, 0);
        let b = purchase_song_inputs(x, 1);
        assert(is_satori411(a) && is_satori411(b), 'purchase preserves markers');
        assert(
            a.score.tonic_keynum == x.score.tonic_keynum
                && b.score.tonic_keynum == x.score.tonic_keynum,
            'keep named base key',
        );
        assert(a.score.tempo_us != b.score.tempo_us, 'named purchase variation');
    }
}
