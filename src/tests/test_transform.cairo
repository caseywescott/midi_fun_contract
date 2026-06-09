use core::array::ArrayTrait;
use koji::composition::melodic_canon::realize_degree;
use koji::composition::symmetry_engine::transpose_pitch_classes;
use koji::composition::transform::{
    apply_op, apply_pipeline, apply_to_object, assemble, arrays_equal_i32, augment_u32,
    combinator_laws_hold, concat_i32, diminish_u32, divide_i32, drop_i32, edge_cases_total, filter_where_i32,
    flatten_i32, gen_permute, gen_rotate, interleave_i32, invert_i32, map_add_i32,
    map_by_position_i32, map_scale_i32, map_where_i32, palindrome_i32, permute_i32, pipeline_total,
    repeat_i32, reverse_i32, rotate_i32, span_i32, take_i32, transpose_i32,
    transpose_pitch_classes_via_i32, trim_i32, EveryNthOp, I32Pair, MusicalObject, Pipeline, PlaneId,
    PlaneOp, Selector, U32Pair,
};

fn push_op(ref pipeline: Pipeline, op: PlaneOp) {
    pipeline.ops.append(op);
}

#[test]
#[available_gas(1000000000000)]
fn test_rotate_laws() {
    let xs = array![0_i32, 1, 2, 3, 4].span();
    let a = rotate_i32(xs, 2);
    let b = rotate_i32(a.span(), 3);
    let c = rotate_i32(xs, 5);
    assert(arrays_equal_i32(b.span(), c.span()), 'rotate add');
    assert(arrays_equal_i32(rotate_i32(xs, 0).span(), xs), 'rotate 0');
}

#[test]
#[available_gas(1000000000000)]
fn test_reverse_invert_laws() {
    let xs = array![0_i32, 2, 4, 5, 7].span();
    assert(arrays_equal_i32(reverse_i32(reverse_i32(xs).span()).span(), xs), 'rev id');
    assert(arrays_equal_i32(invert_i32(invert_i32(xs, 4).span(), 4).span(), xs), 'inv id');
}

#[test]
#[available_gas(1000000000000)]
fn test_map_fusion() {
    let xs = array![10_i32, 20, 30].span();
    let f = map_add_i32(xs, array![1_i32].span());
    let g = map_add_i32(f.span(), array![2_i32].span());
    let fg = map_add_i32(xs, array![3_i32].span());
    assert(arrays_equal_i32(g.span(), fg.span()), 'map fusion');
}

#[test]
#[available_gas(1000000000000)]
fn test_select_map_filter() {
    let xs = array![0_i32, 1, 2, 3, 4, 5].span();
    assert(take_i32(xs, 10).len() == 6, 'take clamp');
    assert(drop_i32(xs, 10).span().len() == 0, 'drop clamp');
    let sub = span_i32(xs, 1, 4);
    assert(sub.len() == 3, 'span len');
    assert(*sub.at(0) == 1, 'span val');

    let mapped = map_by_position_i32(xs, array![100_i32, 200].span());
    assert(*mapped.at(0) == 100, 'map pos 0');
    assert(*mapped.at(1) == 200, 'map pos 1');
    assert(*mapped.at(2) == 100, 'map pos recycle');

    let filtered = filter_where_i32(xs, Selector::EveryNth(2));
    assert(filtered.len() == 3, 'filter nth len');

    let mut op = PlaneOp::Transpose(10);
    let mw = map_where_i32(xs, Selector::Range(U32Pair { a: 2, b: 5 }), @op);
    assert(*mw.at(2) == 12, 'map where hit');
    assert(*mw.at(0) == 0, 'map where miss');
}

#[test]
#[available_gas(1000000000000)]
fn test_rhythm_combine_shape() {
    let lens = array![4_u32, 4, 2, 2, 4].span();
    let aug = augment_u32(lens, 2);
    assert(*aug.at(0) == 8, 'aug');
    let dim = diminish_u32(array![8_u32, 7, 6].span(), 2);
    assert(*dim.at(0) == 4, 'dim div');
    assert(*dim.at(1) == 7, 'dim guard');

    let a = array![1_i32, 2, 3].span();
    let b = array![10_i32, 20].span();
    let il = interleave_i32(a, b);
    assert(il.len() == 5, 'interleave len');
    let cat = concat_i32(a, b);
    assert(cat.len() == 5, 'concat len');

    let tiled = repeat_i32(a, 2);
    assert(tiled.len() == 6, 'repeat');
    assert(trim_i32(tiled.span(), 4).len() == 4, 'trim');

    let groups = divide_i32(a, 2);
    assert(groups.len() == 2, 'divide groups');
    let flat = flatten_i32(@groups);
    assert(arrays_equal_i32(flat.span(), a), 'divide flat');
}

#[test]
#[available_gas(1000000000000)]
fn test_palindrome_permute() {
    let xs = array![1_i32, 2, 3].span();
    let pal = palindrome_i32(xs, false);
    assert(pal.len() == 6, 'pal len');
    let pal_p = palindrome_i32(xs, true);
    assert(pal_p.len() == 5, 'pal pivot');

    let perm = permute_i32(xs, array![2_u32, 0, 1].span());
    assert(*perm.at(0) == 3, 'perm 0');
    assert(*perm.at(1) == 1, 'perm 1');
}

#[test]
#[available_gas(1000000000000)]
fn test_gen_deterministic() {
    let xs = array![0_i32, 1, 2, 3, 4].span();
    let seed: felt252 = 424242;
    let r1 = gen_rotate(seed, xs);
    let r2 = gen_rotate(seed, xs);
    assert(arrays_equal_i32(r1.span(), r2.span()), 'gen rotate det');
    let p1 = gen_permute(seed, xs);
    let p2 = gen_permute(seed, xs);
    assert(arrays_equal_i32(p1.span(), p2.span()), 'gen perm det');
}

#[test]
#[available_gas(1000000000000)]
fn test_pipeline_and_object() {
    let mut pitch_ops: Array<PlaneOp> = ArrayTrait::new();
    pitch_ops.append(PlaneOp::Invert(4));
    pitch_ops.append(PlaneOp::Rotate(2));
    pitch_ops.append(PlaneOp::Repeat(2));
    let pitch_pipe = Pipeline { ops: pitch_ops };

    let mut len_ops: Array<PlaneOp> = ArrayTrait::new();
    len_ops.append(PlaneOp::Rotate(1));
    len_ops.append(PlaneOp::Augment(2));
    let len_pipe = Pipeline { ops: len_ops };

    let mut vel_table: Array<i32> = ArrayTrait::new();
    vel_table.append(110);
    vel_table.append(70);
    vel_table.append(70);
    vel_table.append(90);
    let mut vel_ops: Array<PlaneOp> = ArrayTrait::new();
    vel_ops.append(PlaneOp::MapByPosition(vel_table));
    let vel_pipe = Pipeline { ops: vel_ops };

    let obj = MusicalObject {
        pitches: array![0_i32, 2, 4, 5, 7],
        lengths: array![4_u32, 4, 2, 2, 4],
        velocities: array![100_u8, 80],
        articulations: array![0_u8],
        octave: 7,
    };

    let mut o = apply_to_object(obj, PlaneId::Pitch, @pitch_pipe);
    o = apply_to_object(o, PlaneId::Length, @len_pipe);
    o = apply_to_object(o, PlaneId::Velocity, @vel_pipe);

    assert(o.pitches.len() == 10, 'pitch repeat');
    assert(o.lengths.len() == 5, 'length same');
    assert(*o.velocities.at(0) == 110, 'vel table 0');

    let events = assemble(@o, 0, 60, 0);
    assert(events.len() == 10, 'event count');
    assert(*events.at(0).time == 0, 't0');
    assert(*events.at(1).time == *o.lengths.at(0), 't1');
    assert(*events.at(0).velocity == 110, 'ev vel');
    assert(
        *events.at(0).pitch == realize_degree(7, *o.pitches.at(0), 60, 0),
        'realized pitch',
    );
}

#[test]
#[available_gas(1000000000000)]
fn test_apply_op_pipeline() {
    let xs = array![1_i32, 2, 3].span();
    let op = PlaneOp::Transpose(5);
    let out = apply_op(xs, @op);
    assert(*out.at(0) == 6, 'apply op');

    let mut ops: Array<PlaneOp> = ArrayTrait::new();
    ops.append(PlaneOp::Reverse(()));
    ops.append(PlaneOp::Transpose(1));
    let pipe = Pipeline { ops };
    assert(pipeline_total(xs, @pipe), 'pipeline total');
    let out2 = apply_pipeline(xs, @pipe);
    assert(*out2.at(0) == 4, 'pipe rev tr');
}

#[test]
#[available_gas(1000000000000)]
fn test_validators() {
    assert(combinator_laws_hold(), 'laws');
    assert(edge_cases_total(), 'edge');
}

#[test]
#[available_gas(1000000000000)]
fn test_transpose_pitch_classes_substrate() {
    let pcs = array![0_u8, 3, 6, 9].span();
    let direct = transpose_pitch_classes(pcs, 1);
    let via = transpose_pitch_classes_via_i32(pcs, 1);
    let mut i: u32 = 0;
    loop {
        if i >= direct.len() {
            break;
        }
        assert(*direct.at(i) == *via.at(i), 'pc transpose match');
        i += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_empty_and_recycle_assemble() {
    let obj = MusicalObject {
        pitches: array![0_i32, 2, 4],
        lengths: array![3_u32, 3],
        velocities: array![90_u8, 70],
        articulations: array![0_u8],
        octave: 7,
    };
    let events = assemble(@obj, 0, 60, 0);
    assert(events.len() == 3, 'assemble n');
    assert(*events.at(2).velocity == 90, 'vel recycle');
    assert(*events.at(0).duration == 3, 'dur 0');
    assert(*events.at(1).duration == 3, 'dur 1');
    assert(*events.at(2).duration == 3, 'dur recycle');
}
