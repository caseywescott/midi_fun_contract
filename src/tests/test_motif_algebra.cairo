//! Tests for motif development algebra: group laws, totality, world closure, canon hand-off.

use koji::composition::melodic_canon::{
    all_pairs_consonant, build_canon_for_test, canon_to_ornamented_note_events,
};
use koji::composition::motif_algebra::{
    apply_op, apply_op_to_developed, apply_program, developed_as_canon_leader,
    developed_to_note_events, generate_developed_line, generate_ornamented_canon_from_developed,
    grundgestalt_theme, long_demo_developed_motif, motif_from_degrees, motif_from_world,
    motif_in_world, op_laws_hold, motif_ops_total, program_from_seed, DevelopedMotif, FragmentOp,
    IntervalScaleOp, MotifOp, SequenceOp, StutterOp, snap_to_world, degree_to_pc,
};
use koji::composition::known_symmetric_worlds::registry_entry;
use koji::composition::transform::arrays_equal_i32;

fn theme_durs() -> Array<u32> {
    array![4_u32, 4, 4, 4]
}

#[test]
#[available_gas(1000000000000)]
fn test_op_laws_hold() {
    assert(op_laws_hold(), 'group laws');
}

#[test]
#[available_gas(1000000000000)]
fn test_transpose_compose() {
    let theme = grundgestalt_theme(0);
    let durs = theme_durs();
    let t2 = apply_op(@theme, @durs, MotifOp::Transpose(2));
    let t3 = apply_op_to_theme(@t2, MotifOp::Transpose(3));
    let t5 = apply_op(@theme, @durs, MotifOp::Transpose(5));
    assert(
        arrays_equal_i32(t3.degrees.span(), t5.degrees.span()),
        'Tn Tm = T(n+m)',
    );
}

fn apply_op_to_theme(m: @DevelopedMotif, op: MotifOp) -> DevelopedMotif {
    apply_op_to_developed(m, op)
}

#[test]
#[available_gas(1000000000000)]
fn test_invert_involutory() {
    let theme = grundgestalt_theme(0);
    let durs = theme_durs();
    let inv = apply_op(@theme, @durs, MotifOp::Invert(2));
    let inv2 = apply_op_to_theme(@inv, MotifOp::Invert(2));
    assert(
        arrays_equal_i32(inv2.degrees.span(), theme.degrees.span()),
        'I I = id',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_retrograde_involutory() {
    let theme = grundgestalt_theme(0);
    let durs = theme_durs();
    let rev = apply_op(@theme, @durs, MotifOp::Retrograde(()));
    let rev2 = apply_op_to_theme(@rev, MotifOp::Retrograde(()));
    assert(
        arrays_equal_i32(rev2.degrees.span(), theme.degrees.span()),
        'R R = id',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_sequence_and_fragment() {
    let theme = grundgestalt_theme(0);
    let durs = theme_durs();
    let seq = apply_op(
        @theme,
        @durs,
        MotifOp::Sequence(SequenceOp { step: 1, count: 3 }),
    );
    assert(seq.degrees.len() == 12, 'sequence len');
    let frag = apply_op(
        @theme,
        @durs,
        MotifOp::Fragment(FragmentOp { start: 0, len: 2 }),
    );
    assert(frag.degrees.len() == 2, 'fragment len');
}

#[test]
#[available_gas(1000000000000)]
fn test_program_deterministic() {
    let seed: felt252 = 777777;
    let p1 = program_from_seed(seed, 4);
    let p2 = program_from_seed(seed, 4);
    assert(p1.ops.len() == p2.ops.len(), 'prog len');
    let theme = grundgestalt_theme(1);
    let d1 = apply_program(@theme, @theme_durs(), p1);
    let d2 = apply_program(@theme, @theme_durs(), p2);
    assert(
        arrays_equal_i32(d1.degrees.span(), d2.degrees.span()),
        'program det',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_world_closure_lydian() {
    let entry = registry_entry(7);
    let mask = entry.mask;
    let theme = motif_from_world(4242, mask, 4);
    let durs = array![4_u32, 4, 4, 4];
    let inv = apply_op(@theme, @durs, MotifOp::Invert(0));
    assert(motif_in_world(@inv), 'invert in world');
    let seq = apply_op(
        @theme,
        @durs,
        MotifOp::Sequence(SequenceOp { step: 1, count: 2 }),
    );
    assert(motif_in_world(@seq), 'sequence in world');
}

#[test]
#[available_gas(1000000000000)]
fn test_motif_from_world() {
    let entry = registry_entry(3);
    let m = motif_from_world(42, entry.mask, 4);
    assert(m.degrees.len() == 4, 'world motif len');
    assert(m.world_mask == entry.mask, 'world mask');
}

#[test]
#[available_gas(1000000000000)]
fn test_developed_canon_leader_consonant() {
    let theme = grundgestalt_theme(0);
    let developed = apply_op(
        @theme,
        @theme_durs(),
        MotifOp::Fragment(FragmentOp { start: 0, len: 3 }),
    );
    let leader = developed_as_canon_leader(@developed);
    let canon = build_canon_for_test(
        0, 'developed', array![0_i32, 4].span(), leader, 0,
    );
    assert(all_pairs_consonant(@canon), 'developed canon ok');
}

#[test]
#[available_gas(1000000000000)]
fn test_developed_to_note_events() {
    let developed = generate_developed_line(12345);
    let events = developed_to_note_events(@developed, 60, 0);
    assert(events.len() > 0, 'has events');
}

#[test]
#[available_gas(1000000000000)]
fn test_ops_total_and_stutter() {
    assert(motif_ops_total(), 'ops total');
    let theme = grundgestalt_theme(0);
    let st = apply_op(
        @theme,
        @theme_durs(),
        MotifOp::Stutter(StutterOp { index: 1, reps: 3 }),
    );
    assert(st.degrees.len() == 6, 'stutter len');
}

#[test]
#[available_gas(1000000000000)]
fn test_interval_scale_and_interpolate() {
    let theme = motif_from_degrees(array![0_i32, 4, 8], 12, 0);
    let durs = array![4_u32, 4, 4];
    let scaled = apply_op(
        @theme,
        @durs,
        MotifOp::IntervalScale(IntervalScaleOp { num: 1, den: 2 }),
    );
    assert(scaled.degrees.len() == 3, 'scale len');
    let interp = apply_op(@theme, @durs, MotifOp::Interpolate(2));
    assert(interp.degrees.len() >= 3, 'interp len');
    assert(interp.degrees.len() == interp.durations.len(), 'interp durations');
}

#[test]
#[available_gas(1000000000000)]
fn test_snap_to_world() {
    let entry = registry_entry(7);
    let snapped = snap_to_world(99, 7, entry.mask, 60, 0);
    let pc = degree_to_pc(snapped, 7, 60, 0);
    assert(
        koji::composition::symmetry_engine::has_pitch(entry.mask, pc),
        'snapped in world',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_ornamented_canon_from_developed_consonant() {
    let developed = long_demo_developed_motif();
    let leader_len = developed.degrees.len();
    let (canon, subs) = generate_ornamented_canon_from_developed(
        4242, 0, @developed, 0,
    );
    assert(all_pairs_consonant(@canon), 'ornamented canon ok');
    let events = canon_to_ornamented_note_events(@canon, subs.span());
    assert(events.len() > leader_len, 'ornament expands events');
}
