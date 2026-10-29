use beast_composer_inputs::evolution::{
    EvolutionConfig, EvolutionInputs, MilestoneHash, milestone_blocks, validate_evolution_config,
    validate_evolution_inputs,
};
use crate::composition::evolution::resolve_evolution;

fn config() -> EvolutionConfig {
    EvolutionConfig {
        first_milestone_age: 10,
        initial_unlock_bps: 5000,
        unlock_step_bps: 0,
        max_extra_channels: 5,
        max_tempo_delta_bpm: 2,
        max_velocity_delta: 8,
        ornament_chance_bps: 1000,
    }
}
fn context(staff: u64) -> EvolutionInputs {
    let mut samples = array![];
    for block in milestone_blocks(config(), 100, staff).span() {
        samples.append(MilestoneHash { block_number: *block, block_hash: (*block).into() });
    }
    EvolutionInputs {
        birth_block: 100,
        staff_block: staff,
        drift_group: 9,
        staff_hash: 123,
        milestones: samples.span(),
    }
}
#[test]
fn evolution_uses_exact_staff_prefix_without_second_lag() {
    assert(milestone_blocks(config(), 100, 109).is_empty(), 'before first');
    assert(milestone_blocks(config(), 100, 110) == array![110], 'first exact');
    assert(milestone_blocks(config(), 100, 120) == array![110, 120], 'second exact');
    assert(
        milestone_blocks(config(), 100, 1380) == array![110, 120, 140, 180, 260, 420, 740, 1380],
        'eight exact',
    );
    assert(milestone_blocks(config(), 100, 1000000).len() == 8, 'bounded lifetime');
}
#[test]
fn evolution_skips_only_unreachable_overflow_anchors() {
    assert(
        milestone_blocks(config(), 0xfffffffffffffff6, 0xffffffffffffffff).is_empty(),
        'future overflow',
    );
}
#[test]
fn evolution_permanent_masks_are_monotone_and_feature_cap_is_fixed() {
    let mut cfg = config();
    cfg.initial_unlock_bps = 10000;
    cfg.max_extra_channels = 2;
    let first = resolve_evolution(cfg, context(110), 5).unlocked_extra_mask;
    let later = resolve_evolution(cfg, context(1380), 5).unlocked_extra_mask;
    assert(first == 3 && later == 3, 'fixed eligible set');
    assert(resolve_evolution(cfg, context(110), 1).unlocked_extra_mask == 1, 'role capacity');
}
#[test]
fn evolution_later_lower_feature_never_evicts_earlier_feature() {
    let cfg = config();
    let mut found = false;
    let mut a: felt252 = 1;
    let mut i: u32 = 0;
    while i < 64 && !found {
        let one = array![MilestoneHash { block_number: 110, block_hash: a }];
        let first = resolve_evolution(
            cfg,
            EvolutionInputs {
                birth_block: 100,
                staff_block: 110,
                drift_group: 9,
                staff_hash: 123,
                milestones: one.span(),
            },
            3,
        )
            .unlocked_extra_mask;
        if first / 4 % 2 == 1 && first % 2 == 0 {
            let mut b: felt252 = 1;
            let mut j: u32 = 0;
            while j < 64 && !found {
                let two = array![
                    MilestoneHash { block_number: 110, block_hash: a },
                    MilestoneHash { block_number: 120, block_hash: b }
                ];
                let later = resolve_evolution(
                    cfg,
                    EvolutionInputs {
                        birth_block: 100,
                        staff_block: 120,
                        drift_group: 9,
                        staff_hash: 123,
                        milestones: two.span(),
                    },
                    3,
                )
                    .unlocked_extra_mask;
                if later % 2 == 1 {
                    assert(first & later == first, 'no feature replacement');
                    found = true;
                }
                b += 1;
                j += 1;
            }
        }
        a += 1;
        i += 1;
    }
    assert(found, 'out of order witness');
}
#[test]
fn evolution_replay_ignores_future_milestones_by_rejecting_them() {
    let before = resolve_evolution(config(), context(110), 3);
    let replay = resolve_evolution(config(), context(110), 3);
    assert(before.unlocked_extra_mask == replay.unlocked_extra_mask, 'replay mask');
    assert(before.note_seed == replay.note_seed, 'replay seed');
}
#[test]
#[should_panic(expected: 'staff before birth')]
fn evolution_rejects_prebirth() {
    milestone_blocks(config(), 100, 99);
}
#[test]
#[should_panic(expected: 'invalid milestone count')]
fn evolution_rejects_future_hash_prefix() {
    let samples = array![
        MilestoneHash { block_number: 110, block_hash: 1 },
        MilestoneHash { block_number: 120, block_hash: 2 }
    ];
    validate_evolution_inputs(
        config(),
        EvolutionInputs {
            birth_block: 100,
            staff_block: 110,
            drift_group: 9,
            staff_hash: 1,
            milestones: samples.span(),
        },
    );
}
#[test]
#[should_panic(expected: 'invalid milestone block')]
fn evolution_rejects_wrong_anchor() {
    let samples = array![MilestoneHash { block_number: 109, block_hash: 1 }];
    validate_evolution_inputs(
        config(),
        EvolutionInputs {
            birth_block: 100,
            staff_block: 110,
            drift_group: 9,
            staff_hash: 1,
            milestones: samples.span(),
        },
    );
}
#[test]
#[should_panic(expected: 'missing milestone hash')]
fn evolution_rejects_zero_hash() {
    let samples = array![MilestoneHash { block_number: 110, block_hash: 0 }];
    validate_evolution_inputs(
        config(),
        EvolutionInputs {
            birth_block: 100,
            staff_block: 110,
            drift_group: 9,
            staff_hash: 1,
            milestones: samples.span(),
        },
    );
}
#[test]
#[should_panic(expected: 'missing staff hash')]
fn evolution_rejects_zero_staff_hash() {
    validate_evolution_inputs(config(), EvolutionInputs { staff_hash: 0, ..context(110) });
}
#[test]
#[should_panic(expected: 'invalid unlock probability')]
fn evolution_rejects_probability_overflow() {
    validate_evolution_config(
        EvolutionConfig { initial_unlock_bps: 9999, unlock_step_bps: 1, ..config() },
    );
}
#[test]
#[should_panic(expected: 'no staff variation')]
fn evolution_requires_essential_fresh_variation() {
    validate_evolution_config(
        EvolutionConfig {
            max_tempo_delta_bpm: 0, max_velocity_delta: 0, ornament_chance_bps: 0, ..config(),
        },
    );
}
