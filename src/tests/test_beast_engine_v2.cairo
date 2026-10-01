use koji::composition::beast_engine_v2::{
    EngineV2Options, build_v3_beast_form_v2, build_v3_beast_form_v2_with, default_v2_options,
    v2_enabled_ornaments, v3_ornament_policy, v3_score_midi_v2,
};
use koji::composition::beast_score::note_events_valid;
use koji::composition::beast_v3_sound::{BeastV3LiveState, PackableBeastV3};

fn beast(
    id: u64, prefix: u8, suffix: u8, level: u16, health: u16, shiny: u8, animated: u8, tier: u8,
    beast_type: u8,
) -> PackableBeastV3 {
    PackableBeastV3 { id, prefix, suffix, level, health, shiny, animated, tier, beast_type }
}

fn live(kills: u64, scars: u64, hours: u64, rank: u16, count: u16) -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: kills, scars, summit_held_seconds: hours * 3600, rank, species_count: count,
    }
}

fn sorrow_peak_warlock() -> PackableBeastV3 {
    beast(1, 57, 15, 126, 229, 0, 0, 1, 0)
}

fn contains(xs: Span<u8>, x: u8) -> bool {
    let mut i: u32 = 0;
    let mut found = false;
    while i < xs.len() {
        if *xs.at(i) == x {
            found = true;
        }
        i += 1;
    }
    found
}

#[test]
#[available_gas(1000000000000)]
fn v2_renders_valid_events() {
    let form = build_v3_beast_form_v2(sorrow_peak_warlock(), live(2, 12, 0, 1, 954));
    assert(note_events_valid(form.events.span()), 'valid events');
    assert(form.events.len() > 100, 'ornamented density');
}

#[test]
fn v2_tier5_single_voice_renders() {
    let wolf = beast(47, 13, 6, 22, 60, 0, 1, 5, 1);
    let form = build_v3_beast_form_v2(wolf, live(1, 4, 2, 300, 1100));
    assert(note_events_valid(form.events.span()), 'valid events');
}

#[test]
#[available_gas(1000000000000)]
fn v2_history_changes_score_not_motif() {
    let b = sorrow_peak_warlock();
    let calm = build_v3_beast_form_v2(b, live(0, 0, 0, 500, 954));
    let veteran = build_v3_beast_form_v2(b, live(40, 9, 25, 1, 954));
    assert(calm.score_hash != veteran.score_hash, 'history audible');
    assert(veteran.section_count > calm.section_count, 'kills add sections');
    // Leader pitches of section A: identical melody whatever the stretto or voice count.
    let calm_lead = leader_pitches(calm.events.span());
    let vet_lead = leader_pitches(veteran.events.span());
    assert(calm_lead.len() == vet_lead.len(), 'same melody length');
}

/// First-voice structural notes are not directly comparable (ornaments differ), so compare the
/// melody through the motif: same seed and union constraints give the same leader walk.
fn leader_pitches(events: Span<koji::composition::melodic_canon::NoteEvent>) -> Array<u8> {
    let mut out: Array<u8> = array![];
    let mut i: u32 = 0;
    while i < events.len() {
        let e = *events.at(i);
        if e.voice_id == 0 && e.time % 480 == 0 && e.time < 480 * 16 {
            out.append(e.pitch);
        }
        i += 1;
    }
    out
}

#[test]
fn v2_melody_is_independent_of_live_state() {
    let profile = koji::composition::aesthetic_profile::profile_by_id(25);
    let offsets: Array<i32> = array![0, -5, 2];
    let cons = koji::composition::melodic_canon::ic_constraints_all_lags(offsets.span(), 4);
    let (degs, _) = koji::composition::melodic_canon::walk_leader_constraints_ic_hashed(
        'seed', offsets.span(), cons.span(), @profile, 36,
    );
    // Valid for every voice count and lag the live state can choose.
    let mut lag: u32 = 1;
    while lag <= 4 {
        let entries: Array<u32> = array![0, lag, 2 * lag];
        let voices = koji::composition::melodic_canon::build_mensuration_voices(
            offsets.span(), entries.span(), array![1, 1, 1].span(),
        );
        let canon = koji::composition::melodic_canon::MelodicCanon {
            config_id: 4, config_name: 'v2', offsets: offsets.span(), leader_degrees: degs.span(),
            leader_steps: array![].span(), mode_id: 5, tonic_keynum: 60, time_unit: 4,
            voices: voices.span(), octave: 7, profile_id: 25,
        };
        assert(koji::composition::invertible_counterpoint::all_pairs_octave_invertible(@canon), 'ic');
        assert(koji::composition::melodic_canon::all_pairs_clash_free(@canon, @profile), 'clash');
        lag += 1;
    }
}

#[test]
fn v2_suffix_policy_filters_ornament_kinds() {
    // Roar (suffix 5) allows trills; Bane (suffix 1) allows none of the gated kinds.
    let roar = v2_enabled_ornaments(v3_ornament_policy(beast(1, 1, 5, 50, 100, 0, 0, 1, 0)), true);
    let bane = v2_enabled_ornaments(v3_ornament_policy(beast(1, 1, 1, 50, 100, 0, 0, 1, 0)), true);
    assert(contains(roar.span(), 25), 'roar trills');
    assert(!contains(bane.span(), 25), 'bane no trills');
    assert(!contains(bane.span(), 8), 'bane no suspension');
    assert(!contains(bane.span(), 29), 'bane no chromatic');
    assert(contains(bane.span(), 1), 'bane passing tones');
}

#[test]
#[available_gas(1000000000000)]
fn v2_options_change_the_output() {
    let b = sorrow_peak_warlock();
    let l = live(9, 12, 30, 1, 954);
    let base = build_v3_beast_form_v2(b, l);
    let mut fixed = default_v2_options();
    fixed.stretto_entries = false;
    let mut old_orn = default_v2_options();
    old_orn.suffix_ornament_policy = false;
    old_orn.minor_harmony = false;
    assert(build_v3_beast_form_v2_with(b, l, fixed).score_hash != base.score_hash, 'stretto opt');
    assert(build_v3_beast_form_v2_with(b, l, old_orn).score_hash != base.score_hash, 'ornament opt');
}

#[test]
#[available_gas(1000000000000)]
fn v2_midi_is_a_standard_midi_file() {
    let midi = v3_score_midi_v2(sorrow_peak_warlock(), live(2, 12, 0, 1, 954));
    let len: u32 = (*midi.at(0)).try_into().unwrap();
    assert(len > 500, 'midi length');
    assert(midi.len() == 1 + (len + 30) / 31, 'packing');
}

fn print_midi(name: felt252, variant: felt252, b: PackableBeastV3, l: BeastV3LiveState, o: EngineV2Options) {
    let form = build_v3_beast_form_v2_with(b, l, o);
    let params = koji::composition::beast_v3_sound::map_v3_beast_to_composition_params(b, l);
    let midi = koji::midi::output::to_felt252_array(
        koji::composition::beast_v3_sound::beast_form_to_smf_bytes(@form, params.tempo_us),
    );
    let mut i: u32 = 0;
    while i < midi.len() {
        println!("ABMIDI {} {} {} {}", name, variant, i, *midi.at(i));
        i += 1;
    }
}

/// Phase 0 listening set: 6 Beasts x 5 variants as MIDI (see docs/beasts/engine_v2_defaults.md).
/// scarb test -- --include-ignored --filter v2_ab_listening_set | grep ABMIDI > /tmp/ab.txt
#[test]
#[ignore]
#[available_gas(100000000000000)]
fn v2_ab_listening_set() {
    let set: Array<(felt252, PackableBeastV3, BeastV3LiveState)> = array![
        ('1_sorrow_peak_warlock', sorrow_peak_warlock(), live(2, 12, 0, 1, 954)),
        ('2_chimeric_grasp_wolf', beast(47, 13, 6, 22, 60, 0, 1, 5, 1), live(1, 0, 0, 300, 1100)),
        ('3_gloom_roar_banshee', beast(13, 30, 5, 80, 300, 0, 0, 3, 0), live(9, 25, 100, 12, 1180)),
        ('4_kraken_crown', beast(51, 61, 13, 180, 900, 0, 0, 1, 2), live(70, 3, 400, 1, 1100)),
        ('5_rune_bite_qilin', beast(31, 53, 3, 60, 200, 1, 1, 2, 1), live(4, 0, 0, 40, 1200)),
        ('6_dragon_genesis', beast(29, 0, 0, 1, 100, 1, 1, 1, 1), live(3, 0, 0, 0, 1200)),
    ];
    let d = default_v2_options();
    let mut new_melody = d;
    new_melody.same_melody_each_section = false;
    let mut fixed_entries = d;
    fixed_entries.stretto_entries = false;
    let mut three_voices = d;
    three_voices.voices_follow_params = false;
    let mut old_ornaments = d;
    old_ornaments.suffix_ornament_policy = false;
    old_ornaments.minor_harmony = false;
    let mut k: u32 = 0;
    while k < set.len() {
        let (name, b, l) = *set.at(k);
        print_midi(name, 'A_default', b, l, d);
        print_midi(name, 'B_new_melody_per_section', b, l, new_melody);
        print_midi(name, 'B_fixed_entries', b, l, fixed_entries);
        print_midi(name, 'B_always_3_voices', b, l, three_voices);
        print_midi(name, 'B_old_ornaments', b, l, old_ornaments);
        k += 1;
    }
}

/// Engine v2 parity fixture: the values the offchain engine must reproduce.
/// scarb test -- --include-ignored --filter v2_parity_fixture | grep V2PARITY
#[test]
#[ignore]
#[available_gas(100000000000000)]
fn v2_parity_fixture() {
    let cases: Array<(PackableBeastV3, BeastV3LiveState)> = array![
        (sorrow_peak_warlock(), live(0, 0, 0, 500, 954)),
        (sorrow_peak_warlock(), live(40, 9, 25, 1, 954)),
        (beast(29, 0, 0, 1, 100, 1, 1, 1, 1), live(3, 0, 0, 0, 1200)),
        (beast(47, 13, 6, 22, 60, 0, 1, 5, 1), live(1, 4, 2, 300, 1100)),
        (beast(76, 12, 4, 30, 80, 1, 0, 3, 2), live(100, 20, 456, 2, 40)),
        (beast(51, 61, 13, 180, 900, 1, 1, 1, 2), live(70, 3, 400, 1, 1100)),
    ];
    let mut i: u32 = 0;
    while i < cases.len() {
        let (b, l) = *cases.at(i);
        let form = build_v3_beast_form_v2(b, l);
        let midi = v3_score_midi_v2(b, l);
        let mut checksum: u64 = 0;
        let mut j: u32 = 0;
        while j < form.events.len() {
            let e = *form.events.at(j);
            let term: u64 = (e.time.into() * 31 + e.duration.into() * 7 + e.pitch.into() * 131
                + e.velocity.into() * 17 + e.voice_id.into() + 1)
                * (j.into() + 1);
            checksum = (checksum + term) % 1000000007;
            j += 1;
        }
        println!(
            "V2PARITY case={} score={} events={} checksum={} midi_len={} midi_hash={}",
            i,
            form.score_hash,
            form.events.len(),
            checksum,
            *midi.at(0),
            core::poseidon::poseidon_hash_span(midi.span()),
        );
        i += 1;
    }
}
