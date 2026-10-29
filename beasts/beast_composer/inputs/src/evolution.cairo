//! Frozen finite evolution controls and explicit, manager-resolved chain context.
//! No syscalls: only the manager reads canonical hashes/chooses Live or AtBlock.
use core::num::traits::CheckedAdd;

pub const EVOLUTION_FORMAT_VERSION: u16 = 1;
pub const MILESTONE_COUNT: u32 = 8;

#[derive(Copy, Drop, Debug, Serde, PartialEq, starknet::Store)]
pub struct EvolutionConfig {
    pub first_milestone_age: u64,
    pub initial_unlock_bps: u16,
    pub unlock_step_bps: u16,
    pub max_extra_channels: u8,
    pub max_tempo_delta_bpm: u8,
    pub max_velocity_delta: u8,
    pub ornament_chance_bps: u16,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq)]
pub struct MilestoneHash {
    pub block_number: u64,
    pub block_hash: felt252,
}

#[derive(Copy, Drop, Debug, Serde, PartialEq)]
pub struct EvolutionInputs {
    pub birth_block: u64,
    pub staff_block: u64,
    pub drift_group: felt252,
    pub staff_hash: felt252,
    pub milestones: Span<MilestoneHash>,
}

pub fn validate_evolution_config(x: EvolutionConfig) {
    assert(x.first_milestone_age >= 1, 'zero milestone age');
    assert(x.first_milestone_age <= 0xffffffffffffffff / 128, 'milestone age too large');
    let step: u32 = x.unlock_step_bps.into();
    let last_chance: u32 = x.initial_unlock_bps.into() + 7 * step;
    assert(last_chance <= 10000, 'invalid unlock probability');
    assert(x.max_extra_channels <= 5, 'too many extra channels');
    assert(x.max_tempo_delta_bpm <= 4, 'invalid staff tempo range');
    assert(x.max_velocity_delta <= 16, 'invalid staff velocity range');
    assert(x.ornament_chance_bps <= 10000, 'invalid staff ornaments');
    assert(
        x.max_tempo_delta_bpm > 0 || x.max_velocity_delta > 0 || x.ornament_chance_bps > 0,
        'no staff variation',
    );
}

/// Exact eligible prefix G+A*2^k <= staff, k=0..7. No second ten-block lag:
/// canonical Live already selected staff=current-10 before entering this helper.
/// Overflowed future anchors are unreachable and omitted, never substituted.
pub fn milestone_blocks(config: EvolutionConfig, birth: u64, staff: u64) -> Array<u64> {
    validate_evolution_config(config);
    assert(staff >= birth, 'staff before birth');
    let mut blocks = array![];
    let mut age = config.first_milestone_age;
    let mut i = 0;
    while i < MILESTONE_COUNT {
        let block = match birth.checked_add(age) {
            Option::Some(block) => block,
            Option::None => { break; },
        };
        if block > staff {
            break;
        }
        blocks.append(block);
        i += 1;
        if i < MILESTONE_COUNT {
            age *= 2;
        }
    }
    blocks
}

pub fn validate_evolution_inputs(config: EvolutionConfig, x: EvolutionInputs) {
    let expected = milestone_blocks(config, x.birth_block, x.staff_block);
    assert(x.staff_hash != 0, 'missing staff hash');
    assert(x.milestones.len() == expected.len(), 'invalid milestone count');
    let mut i = 0;
    for sample in x.milestones {
        let sample = *sample;
        assert(sample.block_number == *expected.at(i), 'invalid milestone block');
        assert(sample.block_hash != 0, 'missing milestone hash');
        i += 1;
    }
}
