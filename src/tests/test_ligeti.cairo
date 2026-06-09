//! Tests for the Ligeti micropolyphony layer: the white-key (diatonic) cluster profile that
//! recolors the diatonic 2nd/7th as soft color, the chromatic cluster profile that un-gates the
//! m2/m9, the gliding register-band envelope, and the mensuration (augmentation) canon. The
//! recurring theme: textures the Renaissance/Jazz gates *reject* are exactly what these profiles
//! accept, and they remain clash-free under their own profile by construction.

use koji::composition::aesthetic_profile::{
    profile_ligeti_white, profile_ligeti_micropolyphony, profile_renaissance, profile_jazz,
    vertical_ok, vertical_class, vertical_tier, CLASH, SOFT,
};
use koji::composition::melodic_canon::{
    generate_ligeti_white_canon, generate_ligeti_cluster_canon, generate_ligeti_micro_canon,
    generate_ligeti_banded_canon, generate_ligeti_mensuration_canon, all_pairs_clash_free,
    exact_imitation, no_minor_ninth, mensuration_clash_free, canon_to_mensuration_note_events,
    canon_to_note_events,
};

// ──────────────────────────────────────────────────────────
// Profile tables: the diatonic 2nd is color here, a clash in Renaissance
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(1000000000000)]
fn test_ligeti_white_admits_the_diatonic_second() {
    let white = profile_ligeti_white();
    let ren = profile_renaissance();
    // class 1 = a diatonic 2nd. Renaissance: CLASH (rejected). Ligeti-white: within budget.
    assert(vertical_tier(@ren, 0, 1) == CLASH, 'ren 2nd is clash');
    assert(!vertical_ok(@ren, 0, 1), 'ren rejects 2nd');
    assert(vertical_ok(@white, 0, 1), 'ligeti accepts 2nd');
    // nothing diatonic is a clash under the white profile
    let mut c: i32 = 0;
    loop {
        if c > 6 {
            break;
        }
        assert(vertical_ok(@white, 0, c), 'white accepts all diatonic');
        c += 1;
    };
}

#[test]
#[available_gas(1000000000000)]
fn test_ligeti_micro_ungates_the_halfstep() {
    let micro = profile_ligeti_micropolyphony();
    let jazz = profile_jazz();
    // chromatic class 1 = m2/m9. Jazz: CLASH. Ligeti-micro: SOFT (embraced cluster interval).
    assert(vertical_class(@micro, 0, 1) == 1, 'm2 is class 1');
    assert(!vertical_ok(@jazz, 0, 1), 'jazz rejects m2');
    assert(vertical_tier(@micro, 0, 1) == SOFT, 'micro m2 is soft');
    assert(vertical_ok(@micro, 0, 1), 'micro accepts m2');
    // but it still keeps quality: m9 (13) folds to the same class and is likewise accepted here
    assert(vertical_ok(@micro, 0, 13), 'micro accepts m9');
}

// ──────────────────────────────────────────────────────────
// White keys only: every realized pitch is a natural (no accidentals)
// ──────────────────────────────────────────────────────────

fn is_white_key(pitch: u8) -> bool {
    let pc = pitch % 12;
    // {C,D,E,F,G,A,B} = {0,2,4,5,7,9,11}
    pc == 0 || pc == 2 || pc == 4 || pc == 5 || pc == 7 || pc == 9 || pc == 11
}

#[test]
#[available_gas(4000000000000)]
fn test_white_canons_have_no_accidentals() {
    let mut seed: felt252 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= 24 {
            break;
        }
        let sd = seed * 13 + 6;
        // two-voice octave canon
        let w = generate_ligeti_white_canon(sd);
        let ew = canon_to_note_events(@w);
        let mut k: u32 = 0;
        loop {
            if k >= ew.len() {
                break;
            }
            assert(is_white_key(*ew.at(k).pitch), 'white canon all white');
            k += 1;
        };
        // four-voice cluster
        let c = generate_ligeti_cluster_canon(sd);
        let ec = canon_to_note_events(@c);
        let mut k2: u32 = 0;
        loop {
            if k2 >= ec.len() {
                break;
            }
            assert(is_white_key(*ec.at(k2).pitch), 'cluster all white');
            k2 += 1;
        };
        // mensuration canon
        let mc = generate_ligeti_mensuration_canon(sd, 14);
        let em = canon_to_mensuration_note_events(@mc);
        let mut k3: u32 = 0;
        loop {
            if k3 >= em.len() {
                break;
            }
            assert(is_white_key(*em.at(k3).pitch), 'mensuration all white');
            k3 += 1;
        };
        seed += 1;
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// White on White: the two-voice octave canon
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_white_on_white_canon_clash_free() {
    let white = profile_ligeti_white();
    let mut seed: felt252 = 1;
    let mut i: u32 = 0;
    loop {
        if i >= 16 {
            break;
        }
        let canon = generate_ligeti_white_canon(seed * 11 + 5);
        assert(canon.voices.len() == 2, 'two voices');
        assert(canon.octave == 7, 'diatonic lattice');
        assert(exact_imitation(@canon), 'is a canon');
        assert(all_pairs_clash_free(@canon, @white), 'clash-free under ligeti');
        seed += 1;
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Diatonic cluster: a moving white-key cluster band
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_cluster_canon_is_a_real_cluster() {
    let white = profile_ligeti_white();
    let ren = profile_renaissance();
    let mut seed: felt252 = 3;
    let mut i: u32 = 0;
    loop {
        if i >= 16 {
            break;
        }
        let canon = generate_ligeti_cluster_canon(seed * 7 + 1);
        assert(canon.voices.len() == 4, 'four voices');
        assert(exact_imitation(@canon), 'is a canon');
        // clash-free under the profile that tolerates diatonic clusters
        assert(all_pairs_clash_free(@canon, @white), 'clash-free under ligeti');
        // ...and genuinely a cluster: the SAME canon is NOT clash-free under Renaissance, because
        // it is full of the 2nds Renaissance forbids. This proves the color is present, not merely
        // tolerated.
        assert(!all_pairs_clash_free(@canon, @ren), 'contains diatonic dissonance');
        seed += 1;
        i += 1;
    };
}

#[test]
#[available_gas(2000000000000)]
fn test_cluster_canon_deterministic() {
    let a = generate_ligeti_cluster_canon(123456);
    let b = generate_ligeti_cluster_canon(123456);
    assert(a.leader_degrees.len() == b.leader_degrees.len(), 'same length');
    let mut i: u32 = 0;
    loop {
        if i >= a.leader_degrees.len() {
            break;
        }
        assert(*a.leader_degrees.at(i) == *b.leader_degrees.at(i), 'identical');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Chromatic micropolyphony: half-steps are the idiom
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_micro_canon_clash_free_under_its_own_profile() {
    let micro = profile_ligeti_micropolyphony();
    let jazz = profile_jazz();
    let canon = generate_ligeti_micro_canon(909090);
    assert(canon.voices.len() == 3, 'three voices');
    assert(canon.octave == 12, 'chromatic lattice');
    assert(exact_imitation(@canon), 'is a canon');
    assert(all_pairs_clash_free(@canon, @micro), 'clash-free under micro');
    // The defining inversion: it deliberately contains m2/m9 collisions, so the irreducible
    // "no half-step" guarantee is FALSE and it is NOT clash-free under jazz.
    assert(!no_minor_ninth(@canon), 'cluster contains m2 by design');
    assert(!all_pairs_clash_free(@canon, @jazz), 'jazz would reject the cluster');
}

// ──────────────────────────────────────────────────────────
// Gliding register band (the "moving band")
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_banded_canon_clash_free_and_in_register() {
    let white = profile_ligeti_white();
    let mut seed: felt252 = 2;
    let mut i: u32 = 0;
    loop {
        if i >= 12 {
            break;
        }
        let canon = generate_ligeti_banded_canon(seed * 5 + 9, 20);
        assert(exact_imitation(@canon), 'is a canon');
        assert(all_pairs_clash_free(@canon, @white), 'clash-free banded');
        let events = canon_to_note_events(@canon);
        assert(events.len() > 0, 'produced events');
        let mut k: u32 = 0;
        loop {
            if k >= events.len() {
                break;
            }
            let e = *events.at(k);
            assert(e.pitch >= 24 && e.pitch <= 108, 'pitch in register');
            k += 1;
        };
        seed += 1;
        i += 1;
    };
}

#[test]
#[available_gas(2000000000000)]
fn test_banded_canon_deterministic() {
    let a = generate_ligeti_banded_canon(55555, 18);
    let b = generate_ligeti_banded_canon(55555, 18);
    let mut i: u32 = 0;
    loop {
        if i >= a.leader_degrees.len() {
            break;
        }
        assert(*a.leader_degrees.at(i) == *b.leader_degrees.at(i), 'identical');
        i += 1;
    };
}

// ──────────────────────────────────────────────────────────
// Mensuration (augmentation) canon
// ──────────────────────────────────────────────────────────

#[test]
#[available_gas(2000000000000)]
fn test_mensuration_canon_clash_free() {
    let white = profile_ligeti_white();
    let mut seed: felt252 = 4;
    let mut i: u32 = 0;
    loop {
        if i >= 16 {
            break;
        }
        let canon = generate_ligeti_mensuration_canon(seed * 9 + 2, 16);
        assert(canon.voices.len() == 2, 'two voices');
        assert(exact_imitation(@canon), 'is a canon');
        // the time-sampled (multi-speed) clash check holds under the permissive profile
        assert(mensuration_clash_free(@canon, @white), 'mensuration clash-free');
        seed += 1;
        i += 1;
    };
}

#[test]
#[available_gas(2000000000000)]
fn test_mensuration_follower_is_augmented() {
    // The follower (voice 1) is in 2:1 augmentation: its notes are twice as long as the leader's.
    let canon = generate_ligeti_mensuration_canon(31337, 12);
    let events = canon_to_mensuration_note_events(@canon);
    assert(events.len() > 0, 'produced events');
    let mut leader_dur: u32 = 0;
    let mut follower_dur: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        let e = *events.at(i);
        if e.voice_id == 0 && leader_dur == 0 {
            leader_dur = e.duration;
        }
        if e.voice_id == 1 && follower_dur == 0 {
            follower_dur = e.duration;
        }
        i += 1;
    };
    assert(leader_dur == 4, 'leader at unit speed');
    assert(follower_dur == 8, 'follower 2:1 augmented');
}
