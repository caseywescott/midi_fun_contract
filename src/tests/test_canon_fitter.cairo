//! Offline canon fitter — Cairo verification of fitted leader degree sequences.

use koji::composition::canon_rules::{config_fifth_above, config_fifth_below};
use koji::composition::entry_lag_canon::assemble_entry_lag_canon_from_leader;
use koji::composition::aesthetic_profile::profile_by_id;
use koji::composition::melodic_canon::all_pairs_clash_free;
use koji::composition::melodic_canon::{
    assemble_canon_from_leader, exact_imitation, all_pairs_consonant,
    cadence_lands_on_final, canon_to_note_events, walk_leader,
};

#[test]
#[available_gas(1000000000000)]
fn test_canon_fitter_exact_fifth_above() {
    // Valid fifth-above frame ending on final (degree 0).
    let degs = array![0_i32, 2, 4, 3, 0];
    let canon = assemble_canon_from_leader(0, 0, 60, 7, degs.span());
    assert(exact_imitation(@canon), 'imitation holds');
    assert(all_pairs_consonant(@canon), 'renaissance consonant');
    assert(cadence_lands_on_final(@canon), 'cadence on final');
    let events = canon_to_note_events(@canon);
    assert(events.len() >= 8, 'multi-voice events emitted');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_fitter_walk_leader_roundtrip() {
    // Degrees from the existing generator must re-assemble through the fitter ingress.
    let cfg = config_fifth_above();
    let (degs, _steps) = walk_leader(42, @cfg, 12, true);
    let canon = assemble_canon_from_leader(0, 0, 60, 7, degs.span());
    assert(exact_imitation(@canon), 'walk roundtrip imitation');
    assert(all_pairs_consonant(@canon), 'walk roundtrip consonant');
    assert(cadence_lands_on_final(@canon), 'walk roundtrip cadence');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_fitter_offline_dissonant_fit() {
    // Output from scripts/canon_fitter on fixtures/canon/fit_input/dissonant_steps.json
    let degs = array![0_i32, 2, 1, 3, 2, 1, 0, 0];
    let canon = assemble_canon_from_leader(0, 0, 60, 7, degs.span());
    assert(exact_imitation(@canon), 'offline fit imitation');
    assert(all_pairs_consonant(@canon), 'offline fit consonant');
    assert(cadence_lands_on_final(@canon), 'offline fit cadence');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_fitter_silvercity_lydian() {
    // Offline fit: silvercity.mid in D Lydian → fifth_below (config 1), 15 degree edits.
    let degs = array![
        -3_i32, -5, -4, -4, -6, -6, -8, -8, -10, -10, -9, -8, -5, -4, -3, -2, -4, -3, -5, -4, -6,
        -5, -5, 0,
    ];
    let canon = assemble_canon_from_leader(1, 3, 62, 7, degs.span());
    assert(exact_imitation(@canon), 'silvercity imitation');
    assert(all_pairs_consonant(@canon), 'silvercity consonant');
    assert(cadence_lands_on_final(@canon), 'silvercity cadence');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_fitter_silvercity_entry_lag_lydian() {
    // Renaissance entry-lag search from silvercity MIDI onsets → fifth_above, entries [0, 4].
    let degs = array![
        -3_i32, -4, -3, -4, -6, -5, -8, -9, -9, -10, -9, -7, -5, -2, -3, -1, -3, -3, -4, -4, -6,
        -6, -7, 0,
    ];
    let entries = array![0_u32, 4];
    let canon = assemble_entry_lag_canon_from_leader(0, entries.span(), 3, 62, degs.span());
    assert(exact_imitation(@canon), 'silvercity el imitation');
    assert(all_pairs_consonant(@canon), 'silvercity el consonant');
    assert(*canon.leader_degrees.at(23) == 0, 'leader cadence degree');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_fitter_entry_lag_uniform_lag2() {
    // Offline-validated fifth-above leader with uniform lag-2 entries [0, 2].
    let degs = array![0_i32, 6, 4, 3, -4, -4, 2, 7];
    let entries = array![0_u32, 2];
    let canon = assemble_entry_lag_canon_from_leader(0, entries.span(), 0, 60, degs.span());
    assert(exact_imitation(@canon), 'entry lag imitation');
    assert(all_pairs_consonant(@canon), 'entry lag consonant');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_fitter_extended_maj7_chromatic() {
    // Chromatic maj7 stack (config 7) — semitone leader degrees from tonic C.
    let degs = array![0_i32, -1, 0, -6, 2, -1, 5, 3];
    let canon = assemble_canon_from_leader(7, 0, 60, 12, degs.span());
    let profile = profile_by_id(1);
    assert(exact_imitation(@canon), 'maj7 imitation');
    assert(all_pairs_clash_free(@canon, @profile), 'jazz profile ok');
}

#[test]
#[available_gas(1000000000000)]
fn test_canon_fitter_fifth_below_walk_roundtrip() {
    let cfg = config_fifth_below();
    let (degs, _steps) = walk_leader(17, @cfg, 10, true);
    let canon = assemble_canon_from_leader(1, 0, 60, 7, degs.span());
    assert(exact_imitation(@canon), 'fifth below imitation');
    assert(all_pairs_consonant(@canon), 'fifth below consonant');
}
