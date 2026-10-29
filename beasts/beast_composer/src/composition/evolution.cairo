//! Pure sparse fresh-hash evolution. Hash acquisition and mode/birth policy
//! remain manager responsibilities; this module validates the complete context.
use beast_composer_inputs::evolution::{EvolutionConfig, EvolutionInputs, validate_evolution_inputs};
use core::poseidon::poseidon_hash_span;
use crate::composition::melodic_canon::NoteEvent;

#[derive(Copy, Drop)]
pub struct StaffControls {
    pub unlocked_extra_mask: u8,
    pub note_seed: felt252,
    pub tempo_delta: i64,
    pub max_velocity_delta: u8,
    pub ornament_chance_bps: u16,
}

fn low32(x: felt252) -> u64 {
    let n: u256 = x.into();
    (n % 0x100000000).try_into().unwrap()
}

pub fn resolve_evolution(
    config: EvolutionConfig, x: EvolutionInputs, available_extra: u8,
) -> StaffControls {
    validate_evolution_inputs(config, x);
    let eligible = if available_extra < config.max_extra_channels {
        available_extra
    } else {
        config.max_extra_channels
    };
    let mut mask: u8 = 0;
    let mut bit: u8 = 1;
    let mut feature: u8 = 0;
    while feature < eligible {
        let mut i: u32 = 0;
        for sample in x.milestones {
            let sample = *sample;
            let roll: u256 = poseidon_hash_span(
                array![
                    'BEAST_UNLOCK_V1', x.drift_group, feature.into(), sample.block_number.into(),
                    sample.block_hash,
                ]
                    .span(),
            )
                .into();
            let step: u32 = config.unlock_step_bps.into();
            let chance: u32 = config.initial_unlock_bps.into() + i * step;
            if roll % 10000 < chance.into() {
                mask += bit;
                break;
            }
            i += 1;
        }
        feature += 1;
        bit *= 2;
    }
    let seed = poseidon_hash_span(
        array!['BEAST_STAFF_V1', x.drift_group, x.staff_block.into(), x.staff_hash,].span(),
    );
    let extent: u64 = config.max_tempo_delta_bpm.into();
    let roll = low32(seed) % (2 * extent + 1);
    let roll: u8 = roll.try_into().unwrap();
    let tempo_delta: i64 = Into::<u8, i64>::into(roll)
        - Into::<u8, i64>::into(config.max_tempo_delta_bpm);
    StaffControls {
        unlocked_extra_mask: mask,
        note_seed: seed,
        tempo_delta,
        max_velocity_delta: config.max_velocity_delta,
        ornament_chance_bps: config.ornament_chance_bps,
    }
}

pub fn extra_role_unlocked(mask: u8, index: u32) -> bool {
    let mut bit: u8 = 1;
    let mut i = 0;
    while i < index {
        bit *= 2;
        i += 1;
    }
    mask / bit % 2 == 1
}

/// Note interpretation occurs after written-score role selection. It cannot
/// replace the written sample or alter permanent role membership. This bounded
/// LCG is a cheap expansion of fresh Poseidon-derived staff entropy, not a VRF.
pub fn perform_staff_events(
    events: Span<NoteEvent>, ceiling: u8, controls: StaffControls,
) -> Array<NoteEvent> {
    let mut state = low32(controls.note_seed);
    let mut out = array![];
    let extent: u64 = controls.max_velocity_delta.into();
    for event in events {
        let e = *event;
        state = (1664525 * state + 1013904223) % 0x100000000;
        let roll: u8 = (state % (2 * extent + 1)).try_into().unwrap();
        let delta: i64 = Into::<u8, i64>::into(roll)
            - Into::<u8, i64>::into(controls.max_velocity_delta);
        let velocity: i64 = e.velocity.into() + delta;
        let velocity: u8 = if velocity < 1 {
            1
        } else if velocity > ceiling.into() {
            ceiling
        } else {
            velocity.try_into().unwrap()
        };
        state = (1664525 * state + 1013904223) % 0x100000000;
        if e.duration >= 120 && state % 10000 < controls.ornament_chance_bps.into() {
            let half = e.duration / 2;
            out.append(NoteEvent { duration: half, velocity, ..e });
            // An octave neighbour retains harmonic pitch class and stays in the
            // existing realizer's24..108 range before any mega octave double.
            let pitch = if e.pitch > 96 {
                e.pitch - 12
            } else {
                e.pitch + 12
            };
            out
                .append(
                    NoteEvent {
                        time: e.time + half, duration: e.duration - half, pitch, velocity, ..e,
                    },
                );
        } else {
            out.append(NoteEvent { velocity, ..e });
        }
    }
    out
}
