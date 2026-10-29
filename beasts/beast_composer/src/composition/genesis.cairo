//! The Genesis Track: what every Beast of a species plays by default (special name 0, seed 0),
//! byte-identical to `genesisMidi` in offchain/beast-sound/src/lab.js, which the Beast Sound lab
//! plays (https://beasts.autonomousaudio.net/onchain/lab.html#tab=genesis).
//!
//! - The species composes with a canonical level (50) and health (200), no live history (a neutral
//!   state), and its chosen theme: candidate N is the motif special name N would compose, on the
//!   Genesis Track's own key, ornament style and instruments (0 = the species' own theme).
//! - Spread keys: each species takes the key of a fixed name (prefix (id - 1) mod 69 + 1), played
//!   with the mode's real scale (the composer otherwise realizes only Aeolian, Dorian and
//!   Phrygian);
//!   Nue (33) plays Phrygian.
//! - The full six channels composed (four canon voices, the countersubject, drums), the tier's
//!   Genesis count kept (5, 5, 4, 3, 3): the theme, the lowest canon voice, then drums, the
//!   countersubject and the other voices.
//! - Repeated notes in inner voices (3 or more voices; never the bass, topline or theme) tied off
//! the
//!   strong beats; no pluck on the topline; the balanced mix; the mega sound when shiny.
//! - Default swaps: Harpy (39) and Pegasus (40) play each other's Genesis Track.
//!
//! Generated tables from lab.js (GENESIS_THEMES, GENESIS_SWAPS, GENESIS_MODES, MODE_SCALES); keep
//! them in step with it (scripts/genesis_parity.mjs checks every species, normal and shiny).

use core::dict::{Felt252Dict, Felt252DictTrait};
use core::poseidon::poseidon_hash_span;
use midi::smf::{smf_byte_array, smf_bytes};
use crate::composition::beast_score::BeastForm;
use crate::composition::beast_trait_map::prefix2_ornament_policy;
use crate::composition::beast_v11::{
    DEV_INVERSION, DEV_SEQUENCE, DEV_STRETTO, V11Override, build_v11_score_with,
};
use crate::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, map_v3_beast_to_composition_params,
};
use crate::composition::drift::{DriftClock, layered_drift, nudge_tempo};
use crate::composition::full_midi::{
    Arrangement, SMF_DIVISION, SMF_FORMAT, VoiceRun, Voicing, beast_form_to_full_tracks_arranged,
    mega_lead_pick, voice_runs, voice_stats,
};
use crate::composition::melodic_canon::NoteEvent;
use crate::composition::yeti::{
    YETI, YETI_AVALANCHE_PROGRAM, YETI_AVALANCHE_VOICE, YETI_ROCK_TEMPO_US, yeti_avalanche,
    yeti_key, yeti_ornaments,
};

/// The chosen Genesis theme of species 1..=75 (index id - 1): a special-name candidate, 0 = its
/// own.
const GENESIS_THEMES: [u16; 75] = [
    0, 3, 5, 1, 0, 0, 5, 419, 1, 0, 6, 0, 1176, 1, 7, 0, 4, 0, 837, 452, 511, 1174, 353, 0, 908, 2,
    195, 61, 967, 597, 598, 914, 976, 204, 797, 74, 0, 911, 210, 0, 808, 575, 7, 582, 847, 1018, 0,
    1087, 986, 0, 6, 1115, 496, 196, 1075, 1146, 1180, 559, 1119, 208, 677, 165, 696, 16, 931, 799,
    136, 941, 650, 5, 2, 135, 1156, 965, 1040,
];

/// The chosen theme of a species (0 = its own; species past 75 have none).
pub fn genesis_theme(id: u64) -> u32 {
    if id >= 1 && id <= 75 {
        (*GENESIS_THEMES.span().at((id - 1).try_into().unwrap())).into()
    } else {
        0
    }
}

/// The species whose Genesis Track a species plays (default swaps; itself otherwise).
pub fn genesis_swap(id: u64) -> u64 {
    if id == 39 {
        return 40;
    }
    if id == 40 {
        return 39;
    }
    id
}

/// A chosen mode on the spread key (same tonic): Nue (33) is Phrygian.
pub fn genesis_mode(id: u64, mode_id: u8) -> u8 {
    if id == 33 {
        return 5;
    }
    mode_id
}

/// A mode's scale as named, semitones from the tonic (Locrian, harmonic minor and Dorian #4
/// included).
pub fn named_mode_scale(mode_id: u8) -> Option<Span<u8>> {
    match mode_id {
        4 => Option::Some(array![0, 2, 3, 5, 7, 9, 10].span()),
        5 => Option::Some(array![0, 1, 3, 5, 7, 8, 10].span()),
        6 => Option::Some(array![0, 1, 3, 5, 6, 8, 10].span()),
        7 => Option::Some(array![0, 2, 3, 5, 7, 8, 10].span()),
        8 => Option::Some(array![0, 2, 3, 5, 7, 8, 11].span()),
        26 => Option::Some(array![0, 2, 3, 6, 7, 9, 10].span()),
        _ => Option::None,
    }
}

/// Tier and type of a species 1..=75: tiers in fives within each 25 (Magic, Hunter, Brute).
pub fn species_tier(id: u64) -> u8 {
    (((id - 1) % 25) / 5 + 1).try_into().unwrap()
}

pub fn species_type(id: u64) -> u8 {
    ((id - 1) / 25).try_into().unwrap()
}

fn tier_sections(tier: u8) -> u8 {
    if tier <= 2 {
        4
    } else if tier == 3 {
        3
    } else {
        2
    }
}

fn genesis_channels(tier: u8) -> u32 {
    if tier <= 2 {
        5
    } else if tier == 3 {
        4
    } else {
        3
    }
}

/// No live history: what every Genesis Track composes with.
pub fn neutral_live() -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1,
    }
}

const DRUMS: u32 = 1000;
/// Voice ids the composer uses (four canon voices and the countersubject).
const MAX_VOICES: u32 = 5;

/// mean(a) < mean(b), cross-multiplied.
fn mean_less(sums: Span<u64>, counts: Span<u64>, a: u32, b: u32) -> bool {
    *sums.at(a) * *counts.at(b) < *sums.at(b) * *counts.at(a)
}

fn contains(xs: Span<u32>, x: u32) -> bool {
    for y in xs {
        if *y == x {
            return true;
        }
    }
    false
}

/// The Genesis channels (lab.js `channelPick` with no seed): the theme (voice 0), the lowest canon
/// voice (0..=3, by mean pitch, the first on a tie), then drums, the countersubject (4) and the
/// other canon voices in id order, the first `count` of them. DRUMS stands for the drum track.
fn genesis_pick(sums: Span<u64>, counts: Span<u64>, count: u32) -> Array<u32> {
    let mut low: u32 = 0;
    let mut v: u32 = 1;
    while v <= 3 {
        if *counts.at(v) > 0 && mean_less(sums, counts, v, low) {
            low = v;
        }
        v += 1;
    }
    let mut order: Array<u32> = array![0];
    if low != 0 {
        order.append(low);
    }
    order.append(DRUMS);
    order.append(4);
    let mut v: u32 = 1;
    while v <= 3 {
        if v != low {
            order.append(v);
        }
        v += 1;
    }
    let mut out: Array<u32> = array![];
    let mut i: u32 = 0;
    while i < count && i < order.len() {
        out.append(*order.at(i));
        i += 1;
    }
    out
}

/// Repeated notes in the inner voices held instead of struck again (lab.js `tieRepeats`, 'weak'):
/// with 3 or more voices, never the bass (lowest mean), the topline (highest) or the theme; a note
/// that repeats the one before, starts where it ends, in the same section, off beats 1 and 3, and
/// keeps the tied note within a bar extends it. `picked` are the voices kept, `sums`/`counts` their
/// pitch statistics, `runs` the voice runs of `events`. Returns the kept events voice by voice,
/// each chronological.
fn tie_repeats(
    events: Span<NoteEvent>,
    runs: Span<VoiceRun>,
    picked: Span<u32>,
    sums: Span<u64>,
    counts: Span<u64>,
    section_ticks: u32,
) -> Array<NoteEvent> {
    let mut voices: Array<u32> = array![];
    let mut v: u32 = 0;
    while v < MAX_VOICES {
        if *counts.at(v) > 0 && contains(picked, v) {
            voices.append(v);
        }
        v += 1;
    }
    let mut bass: u32 = *voices.at(0);
    let mut top: u32 = *voices.at(0);
    for v in voices.span() {
        if mean_less(sums, counts, *v, bass) {
            bass = *v;
        }
        if mean_less(sums, counts, top, *v) {
            top = *v;
        }
    }
    let tie_any = voices.len() >= 3;
    let mut out: Array<NoteEvent> = array![];
    for v in voices.span() {
        let v = *v;
        if !(tie_any && v != 0 && v != bass && v != top) {
            for r in runs {
                if r.voice == v {
                    out.append_span(events.slice(r.start, r.len));
                }
            }
            continue;
        }
        let mut prev: Option<NoteEvent> = Option::None;
        for r in runs {
            if r.voice == v {
                for e in events.slice(r.start, r.len) {
                    let e = *e;
                    match prev {
                        Option::Some(p) => {
                            if p.pitch == e.pitch && p.time
                                + p.duration == e.time && p.time
                                    / section_ticks == e.time
                                    / section_ticks && p.duration
                                + e.duration <= 1920 && e.time % 960 != 0 {
                                prev =
                                    Option::Some(
                                        NoteEvent { duration: p.duration + e.duration, ..p },
                                    );
                            } else {
                                out.append(p);
                                prev = Option::Some(e);
                            }
                        },
                        Option::None => { prev = Option::Some(e); },
                    }
                }
            }
        }
        if let Option::Some(p) = prev {
            out.append(p);
        }
    }
    out
}

/// The shared voice runs' statistics and the tie pass over them against the per-voice scans they
/// replaced.
#[cfg(test)]
mod run_tests {
    use core::dict::{Felt252Dict, Felt252DictTrait};
    use crate::composition::full_midi::{voice_runs, voice_stats};
    use crate::composition::melodic_canon::NoteEvent;
    use super::{MAX_VOICES, contains, mean_less, tie_repeats};

    /// `voice_stats` as it was: two dictionaries filled event by event.
    fn dict_stats(events: Span<NoteEvent>) -> (Array<u64>, Array<u64>) {
        let mut s: Felt252Dict<u64> = Default::default();
        let mut n: Felt252Dict<u64> = Default::default();
        for e in events {
            let k: felt252 = e.voice_id.into();
            s.insert(k, s.get(k) + e.pitch.into());
            n.insert(k, n.get(k) + 1);
        }
        let mut sums: Array<u64> = array![];
        let mut counts: Array<u64> = array![];
        let mut v: u32 = 0;
        while v < MAX_VOICES {
            sums.append(s.get(v.into()));
            counts.append(n.get(v.into()));
            v += 1;
        }
        (sums, counts)
    }

    /// `tie_repeats` as it was: one pass over all the events per kept voice.
    fn scan_tie_repeats(
        events: Span<NoteEvent>,
        picked: Span<u32>,
        sums: Span<u64>,
        counts: Span<u64>,
        section_ticks: u32,
    ) -> Array<NoteEvent> {
        let mut voices: Array<u32> = array![];
        let mut v: u32 = 0;
        while v < MAX_VOICES {
            if *counts.at(v) > 0 && contains(picked, v) {
                voices.append(v);
            }
            v += 1;
        }
        let mut bass: u32 = *voices.at(0);
        let mut top: u32 = *voices.at(0);
        for v in voices.span() {
            if mean_less(sums, counts, *v, bass) {
                bass = *v;
            }
            if mean_less(sums, counts, top, *v) {
                top = *v;
            }
        }
        let tie_any = voices.len() >= 3;
        let mut out: Array<NoteEvent> = array![];
        for v in voices.span() {
            let v = *v;
            if !(tie_any && v != 0 && v != bass && v != top) {
                for e in events {
                    if e.voice_id == v {
                        out.append(*e);
                    }
                }
                continue;
            }
            let mut prev: Option<NoteEvent> = Option::None;
            for e in events {
                if e.voice_id != v {
                    continue;
                }
                let e = *e;
                match prev {
                    Option::Some(p) => {
                        if p.pitch == e.pitch && p.time
                            + p.duration == e.time && p.time
                                / section_ticks == e.time
                                / section_ticks && p.duration
                            + e.duration <= 1920 && e.time % 960 != 0 {
                            prev =
                                Option::Some(NoteEvent { duration: p.duration + e.duration, ..p });
                        } else {
                            out.append(p);
                            prev = Option::Some(e);
                        }
                    },
                    Option::None => { prev = Option::Some(e); },
                }
            }
            if let Option::Some(p) = prev {
                out.append(p);
            }
        }
        out
    }

    fn next(ref seed: u64) -> u64 {
        seed = (seed * 1103515245 + 12345) % 2147483648;
        seed / 65536
    }

    /// `count` runs of 1..=4 events over voices 0..voices (ids from MAX_VOICES on included), each
    /// voice chronological, the pitches few so that repeats are common and the starts
    /// sometimes adjacent.
    fn random_events(ref seed: u64, count: u32, voices: u64) -> Array<NoteEvent> {
        let mut cursors: Felt252Dict<u32> = Default::default();
        let mut events: Array<NoteEvent> = array![];
        let mut i: u32 = 0;
        while i < count {
            let voice: u32 = (next(ref seed) % voices).try_into().unwrap();
            let mut left = 1 + next(ref seed) % 4;
            while left > 0 {
                let r = next(ref seed);
                let gap: u32 = if r % 8 == 0 {
                    480
                } else {
                    0
                };
                let time = cursors.get(voice.into()) + gap;
                let duration: u32 = (240 * (1 + (r / 8) % 4)).try_into().unwrap();
                let pitch: u8 = (60 + (r / 32) % 2).try_into().unwrap();
                events.append(NoteEvent { time, duration, pitch, velocity: 90, voice_id: voice });
                cursors.insert(voice.into(), time + duration);
                left -= 1;
            }
            i += 1;
        }
        events
    }

    fn assert_same_events(got: Span<NoteEvent>, want: Span<NoteEvent>) {
        assert(got.len() == want.len(), 'event count');
        let mut i: u32 = 0;
        while i < got.len() {
            let (g, w) = (*got.at(i), *want.at(i));
            assert(g.time == w.time && g.duration == w.duration, 'event time');
            assert(g.pitch == w.pitch && g.velocity == w.velocity, 'event pitch');
            assert(g.voice_id == w.voice_id, 'event voice');
            i += 1;
        }
    }

    fn assert_same_stats(got: Span<u64>, want: Span<u64>) {
        assert(got.len() == MAX_VOICES && want.len() == MAX_VOICES, 'stats length');
        let mut v: u32 = 0;
        while v < MAX_VOICES {
            assert(*got.at(v) == *want.at(v), 'stats value');
            v += 1;
        }
    }

    /// Bit `v` of `mask`.
    fn bit(mask: u32, v: u32) -> bool {
        (mask / *array![1, 2, 4, 8, 16].span().at(v)) % 2 == 1
    }

    /// Cases `from..to` of 60 (all 60 are drawn in order, so a case's events do not depend on the
    /// split; a test per range keeps each test run small).
    fn runs_match_the_scans(from: u32, to: u32) {
        let mut seed: u64 = 20240607;
        let mut merged: u32 = 0;
        let mut case: u32 = 0;
        while case < 60 {
            let events = random_events(ref seed, 3 + case, 1 + (case % 7).into());
            if case < from || case >= to {
                case += 1;
                continue;
            }
            let section_ticks: u32 = *array![960, 1920, 3840].span().at(case % 3);
            let runs = voice_runs(events.span());
            let (sums, counts) = voice_stats(runs.span(), MAX_VOICES - 1);
            let (want_sums, want_counts) = dict_stats(events.span());
            assert_same_stats(sums.span(), want_sums.span());
            assert_same_stats(counts.span(), want_counts.span());
            // every set of kept voices, with and without the drums
            let mut mask: u32 = 1;
            while mask < 64 {
                let mut picked: Array<u32> = array![];
                let mut kept = false;
                let mut kept_events: u64 = 0;
                let mut v: u32 = 0;
                while v < MAX_VOICES {
                    if bit(mask, v) {
                        picked.append(v);
                        kept = kept || *counts.at(v) > 0;
                        kept_events += *counts.at(v);
                    }
                    v += 1;
                }
                if mask >= 32 {
                    picked.append(1000);
                }
                // a set with no voice in the track panics, in the same way before and after
                if kept {
                    let got = tie_repeats(
                        events.span(),
                        runs.span(),
                        picked.span(),
                        sums.span(),
                        counts.span(),
                        section_ticks,
                    );
                    let want = scan_tie_repeats(
                        events.span(), picked.span(), sums.span(), counts.span(), section_ticks,
                    );
                    assert_same_events(got.span(), want.span());
                    merged += (kept_events - got.len().into()).try_into().unwrap();
                }
                mask += 1;
            }
            case += 1;
        }
        assert(merged > 0, 'no note was tied');
    }

    #[test]
    #[available_gas(100000000000)]
    fn test_runs_match_the_scans_0() {
        runs_match_the_scans(0, 22);
    }

    #[test]
    #[available_gas(100000000000)]
    fn test_runs_match_the_scans_1() {
        runs_match_the_scans(22, 33);
    }

    #[test]
    #[available_gas(100000000000)]
    fn test_runs_match_the_scans_2() {
        runs_match_the_scans(33, 41);
    }

    #[test]
    #[available_gas(100000000000)]
    fn test_runs_match_the_scans_3() {
        runs_match_the_scans(41, 48);
    }

    #[test]
    #[available_gas(100000000000)]
    fn test_runs_match_the_scans_4() {
        runs_match_the_scans(48, 54);
    }

    #[test]
    #[available_gas(100000000000)]
    fn test_runs_match_the_scans_5() {
        runs_match_the_scans(54, 60);
    }

    #[test]
    fn test_no_events_have_no_voices() {
        let events: Array<NoteEvent> = array![];
        let runs = voice_runs(events.span());
        let (sums, counts) = voice_stats(runs.span(), MAX_VOICES - 1);
        assert_same_stats(sums.span(), array![0, 0, 0, 0, 0].span());
        assert_same_stats(counts.span(), array![0, 0, 0, 0, 0].span());
    }

    #[test]
    #[should_panic(expected: ('Index out of bounds',))]
    fn test_tie_repeats_without_a_kept_voice_panics() {
        let events: Array<NoteEvent> = array![];
        let runs = voice_runs(events.span());
        let (sums, counts) = voice_stats(runs.span(), MAX_VOICES - 1);
        tie_repeats(events.span(), runs.span(), array![0].span(), sums.span(), counts.span(), 1920);
    }
}

/// The Genesis Track MIDI (self-contained, for onchain-midi-player) of a Beast: its species' (after
/// the default swaps), with the mega arrangement when the Beast is shiny. Species past 75 compose
/// with their own tier and type and their own theme.
pub fn genesis_smf_bytes(beast: PackableBeastV3) -> Array<u8> {
    smf_bytes(SMF_FORMAT, SMF_DIVISION, genesis_tracks(beast).span())
}

/// The same file as a `ByteArray` (what `IMidiProvider::get_midi` returns), packed straight from
/// the track bodies instead of from one copy of the whole file.
pub fn genesis_byte_array(beast: PackableBeastV3) -> ByteArray {
    smf_byte_array(SMF_FORMAT, SMF_DIVISION, genesis_tracks(beast).span())
}

/// A name track (the Beast Special Song): `sampleTrackMidi` at special name (prefix, suffix), seed
/// 0, with the Genesis defaults. Everything is the Genesis Track's (channels, ties, mix,
/// instruments, sections, the species' picked theme) except: no swap, the name's key, register and
/// ornament style played in its real scale, and trills when the name's style has them.
pub fn name_track_smf_bytes(beast: PackableBeastV3, prefix: u8, suffix: u8) -> Array<u8> {
    assert(prefix >= 1 && prefix <= 69 && suffix >= 1 && suffix <= 18, 'invalid special name');
    compose(beast, prefix, suffix, 0, Option::None)
}

/// A bought track: `sampleTrackMidi` with the track's seed (a block hash, never 0) on the Beast's
/// key (its special name's, or its species' spread key without one) and the species' picked theme.
/// The seed picks the treatment (`trackTreatment`: development, episode direction, 2-4 sections,
/// spacing, the key plan's side, the rhythm cells) and the channels (`channelCount`: 3-6, six in
/// 25; `channelPick`: the theme, the lowest voice, then a seeded order). No default swap.
pub fn seeded_track_smf_bytes(
    beast: PackableBeastV3, prefix: u8, suffix: u8, seed: felt252,
) -> Array<u8> {
    assert(seed != 0, 'seed 0 is the Genesis seed');
    assert(prefix <= 69 && suffix <= 18 && (prefix == 0) == (suffix == 0), 'invalid special name');
    compose(beast, prefix, suffix, seed, Option::None)
}

/// Any of a Beast's songs on a day of drift: the Genesis Track (prefix 0, seed 0), a name track
/// (seed 0) or a bought track (a seed), with the layered drift of `clock` (`drift.cairo`; none =
/// as written). The drift belongs to the Beast (its species and special name).
pub fn song_smf_bytes(
    beast: PackableBeastV3, prefix: u8, suffix: u8, seed: felt252, drift: Option<DriftClock>,
) -> Array<u8> {
    assert(prefix <= 69 && suffix <= 18 && (prefix == 0) == (suffix == 0), 'invalid special name');
    compose(beast, prefix, suffix, seed, drift)
}

/// A track's treatment from its seed (lab.js `trackTreatment`).
#[derive(Copy, Drop)]
struct Treatment {
    development: u8,
    direction: i32,
    sections: u8,
    spacing: u8,
    flip_side: bool,
    rhythm_seed: felt252,
}

fn low32(x: felt252) -> u32 {
    let w: u256 = x.into();
    (w % 0x100000000).try_into().unwrap()
}

fn treatment(seed: felt252) -> Treatment {
    let s = low32(poseidon_hash_span(array!['BEAST_TRACK', seed].span()));
    let t = low32(poseidon_hash_span(array!['BEAST_TRACK_2', seed].span()));
    Treatment {
        // DEVELOPMENTS = [inversion, stretto, sequence]
        development: match s % 3 {
            0 => DEV_INVERSION,
            1 => DEV_STRETTO,
            _ => DEV_SEQUENCE,
        },
        direction: match (s / 4) % 3 {
            0 => 1,
            1 => -1,
            _ => 0,
        },
        sections: (2 + (s / 16) % 3).try_into().unwrap(),
        spacing: ((s / 128) % 3).try_into().unwrap(),
        flip_side: (s / 512) % 2 == 1,
        rhythm_seed: t.into() * 0x10000000 + s.into(),
    }
}

/// The channel count of a seeded track: 3 (30%), 4 (40%), 5 (26%) or 6 (4%).
fn seeded_channels(seed: felt252) -> u32 {
    let roll: u256 = poseidon_hash_span(array!['BEAST_CHANNELS', seed].span()).into() % 100;
    if roll < 30 {
        3
    } else if roll < 70 {
        4
    } else if roll < 96 {
        5
    } else {
        6
    }
}

/// The channels of a seeded track: the theme, the lowest canon voice, then the other canon voices,
/// the countersubject and the drums in an order shuffled by the seed (Fisher-Yates from the end,
/// the hash divided by 7 after each swap).
fn seeded_pick(sums: Span<u64>, counts: Span<u64>, count: u32, seed: felt252) -> Array<u32> {
    let mut low: u32 = 0;
    let mut v: u32 = 1;
    while v <= 3 {
        if *counts.at(v) > 0 && mean_less(sums, counts, v, low) {
            low = v;
        }
        v += 1;
    }
    let mut rest: Felt252Dict<u32> = Default::default();
    let mut n: u32 = 0;
    let mut v: u32 = 1;
    while v <= 3 {
        if v != low && *counts.at(v) > 0 {
            rest.insert(n.into(), v);
            n += 1;
        }
        v += 1;
    }
    rest.insert(n.into(), 4);
    rest.insert((n + 1).into(), DRUMS);
    n += 2;
    let mut h: u256 = poseidon_hash_span(array!['BEAST_CHANNEL_ORDER', seed].span()).into();
    let mut i = n - 1;
    while i > 0 {
        let j: u32 = (h % (i + 1).into()).try_into().unwrap();
        let a = rest.get(i.into());
        let b = rest.get(j.into());
        rest.insert(i.into(), b);
        rest.insert(j.into(), a);
        h = h / 7;
        i -= 1;
    }
    let mut out: Array<u32> = array![0];
    if low != 0 {
        out.append(low);
    }
    let mut k: u32 = 0;
    while k < n {
        out.append(rest.get(k.into()));
        k += 1;
    }
    let mut kept: Array<u32> = array![];
    let mut k: u32 = 0;
    while k < count && k < out.len() {
        kept.append(*out.at(k));
        k += 1;
    }
    kept
}

/// The Genesis Track (prefix 0, seed 0), a name track (seed 0) or a bought track (a seed).
// On purpose (CASM size): one copy of `compose_tracks` for all of them, whatever constant arguments
// the callers pass; the Genesis Track has its own copy (`genesis_tracks`).
#[inline(never)]
fn compose(
    beast: PackableBeastV3, prefix: u8, suffix: u8, seed: felt252, drift: Option<DriftClock>,
) -> Array<u8> {
    smf_bytes(SMF_FORMAT, SMF_DIVISION, compose_tracks(beast, prefix, suffix, seed, drift).span())
}

/// The track bodies of the Genesis Track. The compiler emits a copy of `compose_tracks` for these
/// constant arguments, folded to the Genesis Track, so a class that plays only that carries none of
/// the name, bought and drift code (a class that plays the others as well holds both copies).
fn genesis_tracks(beast: PackableBeastV3) -> Array<Array<u8>> {
    compose_tracks(beast, 0, 0, 0, Option::None)
}

/// The track bodies of `compose`'s file.
// On purpose (CASM size): `== 0` tests rather than `!= 0`. Const folding of a call with constant
// arguments sees through `==` but not through `!(==)` (`bool_not`), which `!=` is, so with `!=` the
// unreachable branches stay in the Genesis copy.
fn compose_tracks(
    beast: PackableBeastV3, prefix: u8, suffix: u8, seed: felt252, drift: Option<DriftClock>,
) -> Array<Array<u8>> {
    let unnamed = prefix == 0;
    let unseeded = seed == 0;
    let tm = if unseeded {
        Option::None
    } else {
        Option::Some(treatment(seed))
    };
    let src = if unnamed && unseeded {
        genesis_swap(beast.id)
    } else {
        beast.id
    };
    let (tier, beast_type) = if src >= 1 && src <= 75 {
        (species_tier(src), species_type(src))
    } else {
        (beast.tier, beast.beast_type)
    };
    let g = PackableBeastV3 {
        id: src,
        prefix: 0,
        suffix: 0,
        level: 50,
        health: 200,
        shiny: 0,
        animated: 0,
        tier,
        beast_type,
    };
    let live = neutral_live();
    let motif = genesis_theme(src);
    let cb = if motif > 0 {
        PackableBeastV3 {
            prefix: ((motif - 1) / 18 + 1).try_into().unwrap(),
            suffix: ((motif - 1) % 18 + 1).try_into().unwrap(),
            ..g,
        }
    } else {
        g
    };
    let pg = map_v3_beast_to_composition_params(g, live);
    let spread = PackableBeastV3 {
        prefix: ((src - 1) % 69 + 1).try_into().unwrap(),
        suffix: ((src - 1) % 18 + 1).try_into().unwrap(),
        ..g,
    };
    let ks = map_v3_beast_to_composition_params(spread, live);
    let mode = genesis_mode(src, ks.mode_id);
    let sections = match tm {
        Option::Some(t) => t.sections,
        Option::None => tier_sections(tier),
    };
    let (mut rhythm_seed, mut flip_side, development, mut direction, spacing) = match tm {
        Option::Some(t) => (
            Option::Some(t.rhythm_seed),
            Option::Some(t.flip_side),
            Option::Some(t.development),
            Option::Some(t.direction),
            Option::Some(t.spacing),
        ),
        Option::None => (Option::None, Option::None, Option::None, Option::None, Option::None),
    };
    // the day's drift: the month's rhythm, the day's knob (key plan side or episode direction; the
    // tempo is nudged below), the week's channel order
    let dr = match drift {
        Option::Some(c) => Option::Some(layered_drift(src, prefix, suffix, c)),
        Option::None => Option::None,
    };
    if let Option::Some(d) = dr {
        if let Option::Some(r) = d.rhythm {
            rhythm_seed = Option::Some(r);
        }
        if d.day_knob == 0 {
            flip_side = Option::Some(flip_side != Option::Some(true));
        } else if d.day_knob == 1 {
            let now: i32 = match direction {
                Option::Some(x) => x,
                Option::None => 0 // no history: the episodes alternate
            };
            direction = Option::Some(if now == 0 {
                1
            } else {
                -now
            });
        }
    }
    let ov = if unnamed {
        V11Override {
            voice_count: Option::Some(4),
            section_count: Option::Some(sections),
            mode_id: Option::Some(mode),
            tonic_keynum: Option::Some(ks.tonic_keynum),
            register_band: Option::Some(ks.register_band),
            ornament_density: Option::Some(pg.ornament_density),
            name_variant_id: Option::Some(0),
            use_countersubject: Option::Some(true),
            scale: named_mode_scale(mode),
            trill: Option::Some(false),
            rhythm_seed,
            flip_side,
            development,
            direction,
            spacing,
        }
    } else {
        let kn = map_v3_beast_to_composition_params(PackableBeastV3 { prefix, suffix, ..g }, live);
        V11Override {
            voice_count: Option::Some(4),
            section_count: Option::Some(sections),
            mode_id: Option::Some(kn.mode_id),
            tonic_keynum: Option::Some(kn.tonic_keynum),
            register_band: Option::Some(kn.register_band),
            ornament_density: Option::Some(kn.ornament_density),
            name_variant_id: Option::Some(0),
            use_countersubject: Option::Some(true),
            scale: named_mode_scale(kn.mode_id),
            trill: Option::Some(prefix2_ornament_policy(suffix - 1).allow_trill),
            rhythm_seed,
            flip_side,
            development,
            direction,
            spacing,
        }
    };
    let scale_used = ov.scale;
    let score = build_v11_score_with(cb, live, ov);
    let p = score.params;
    // the Genesis channels, then ties in the inner voices (statistics of the full score: the kept
    // voices' are the same, since a channel is kept or dropped whole)
    let runs = voice_runs(score.events.span());
    let (sums, counts) = voice_stats(runs.span(), MAX_VOICES - 1);
    let count = if unseeded {
        genesis_channels(tier)
    } else {
        seeded_channels(seed)
    };
    let rotate = match dr {
        Option::Some(d) => d.rotate,
        Option::None => Option::None,
    };
    let picked = if let Option::Some(r) = rotate {
        seeded_pick(sums.span(), counts.span(), count, r)
    } else if unseeded {
        genesis_pick(sums.span(), counts.span(), count)
    } else {
        seeded_pick(sums.span(), counts.span(), count, seed)
    };
    let mut events = tie_repeats(
        score.events.span(),
        runs.span(),
        picked.span(),
        sums.span(),
        counts.span(),
        score.section_ticks,
    );
    // the Yeti special on every Yeti track: ornaments by the track's profile, then the avalanche
    let yeti = src == YETI;
    if yeti {
        let key = yeti_key(p.tonic_keynum, p.mode_id, scale_used);
        events =
            yeti_ornaments(
                events.span(), score.section_ticks, key, p.ornament_density, src, prefix, suffix,
            );
        events =
            yeti_avalanche(
                events.span(), score.section_ticks, p.section_count.into(), p.tonic_keynum, key,
            );
    }
    let form = BeastForm {
        events,
        score_hash: 0,
        section_count: p.section_count,
        length_ticks: p.section_count.into() * score.section_ticks,
    };
    let mut tempo_us = if yeti {
        YETI_ROCK_TEMPO_US
    } else {
        p.tempo_us
    };
    if let Option::Some(d) = dr {
        if d.day_knob >= 2 {
            tempo_us = nudge_tempo(tempo_us, d.delta_bpm);
        }
    }
    beast_form_to_full_tracks_arranged(
        @form,
        tempo_us,
        p.tier,
        Option::Some(
            Voicing {
                beast_type,
                species_id: p.species_id,
                name_variant_id: p.name_variant_id,
                voice_count: p.voice_count,
                use_countersubject: p.use_countersubject,
            },
        ),
        beast.shiny == 1,
        mega_lead_pick(p.species_id, p.name_variant_id),
        Arrangement {
            top_lead: true,
            balanced: true,
            drums: contains(picked.span(), DRUMS),
            rock: yeti,
            extra: if yeti {
                Option::Some((YETI_AVALANCHE_VOICE, YETI_AVALANCHE_PROGRAM))
            } else {
                Option::None
            },
            programs: Option::None,
        },
    )
}

/// The same, packed 31 bytes per felt after the byte length.
pub fn genesis_midi(beast: PackableBeastV3) -> Array<felt252> {
    midi::pack::to_felt252_array(genesis_smf_bytes(beast).span())
}

#[cfg(test)]
mod tests {
    use crate::composition::beast_v3_sound::PackableBeastV3;
    use super::{genesis_smf_bytes, song_smf_bytes, species_tier, species_type};

    /// `genesis_smf_bytes` composes with the copy of `compose_tracks` folded to the Genesis Track,
    /// `song_smf_bytes` with the general copy (`compose` is `#[inline(never)]`): the same file.
    fn same_file(id: u64, tier: u8, beast_type: u8, shiny: u8) {
        let b = PackableBeastV3 {
            id, prefix: 0, suffix: 0, level: 50, health: 200, shiny, animated: 0, tier, beast_type,
        };
        assert!(
            genesis_smf_bytes(b) == song_smf_bytes(b, 0, 0, 0, Option::None),
            "species {} shiny {}",
            id,
            shiny,
        );
    }

    #[test]
    #[available_gas(1000000000000)]
    fn the_genesis_copy_composes_what_the_general_copy_does() {
        // The lightest file, a default swap (Harpy), the Yeti (shiny), a species past 75.
        same_file(21, species_tier(21), species_type(21), 0);
        same_file(39, species_tier(39), species_type(39), 0);
        same_file(68, species_tier(68), species_type(68), 1);
        same_file(76, 3, 1, 0);
    }
}

/// Internally materialize the fixed purchase sample. Zero is ordinary seed data;
/// the legacy zero-as-Genesis sentinel is not part of this API.
pub fn generate_recipe_inputs(
    base: beast_composer_inputs::GenerationInputs, seed: felt252,
) -> beast_composer_inputs::ComposerInputs {
    use beast_composer_inputs::{ChannelPolicy, ComposerInputs};
    beast_composer_inputs::validate_generation_inputs(base);
    let mut song = base.base_song;
    let t = treatment(seed);
    song.score.section_count = t.sections;
    song.treatment.rhythm_seed = t.rhythm_seed;
    song.treatment.flip_side = t.flip_side;
    song.treatment.development = t.development;
    song.treatment.direction = if t.direction == 0 {
        0
    } else if t.direction == 1 {
        1
    } else {
        2
    };
    song.treatment.spacing = t.spacing;
    // Explicit paid-sample musical policy; zero remains ordinary seed data.
    song.treatment.section_rhythm = true;
    // Independent purchase-shape choices keep the edition's motif, home key and
    // program identity. They alter actual written entrances/counterpoint, not
    // metadata, tiny tempo differences or a later performance's velocity.
    let shape: u256 = poseidon_hash_span(array!['BEAST_SAMPLE_SHAPE_V1', seed].span()).into();
    let shape: u16 = (shape % 512).try_into().unwrap();
    let lag: u8 = (shape % 4).try_into().unwrap();
    song.score.stretto_lag = 1 + (song.score.stretto_lag - 1 + lag) % 4;
    song.score.use_inversion = song.score.use_inversion != (shape / 4 % 2 == 1);
    let density: u8 = (shape / 8 % 8).try_into().unwrap();
    song.score.ornament_density = (song.score.ornament_density + density) % 8;
    song.treatment.trill = song.treatment.trill != (shape / 64 % 2 == 1);
    if song.score.voice_count > 2 {
        let fewer: u8 = (shape / 128 % 2).try_into().unwrap();
        song.score.voice_count -= fewer;
    }
    song.score.use_countersubject = song.score.use_countersubject && shape / 256 % 2 == 0;
    // The written role count is computed after shape selection. No absent voice
    // may enter the channel picker, nor may a sample enable an unauthored CS.
    let roles: u32 = song.score.voice_count.into()
        + if song.score.use_countersubject {
            1
        } else {
            0
        }
        + 1;
    let count = seeded_channels(seed);
    song
        .arrangement
        .channel_count =
            if count < roles {
                count.try_into().unwrap()
            } else {
                roles.try_into().unwrap()
            };
    song.arrangement.channel_policy = ChannelPolicy::Seeded(seed);
    let result = ComposerInputs::Song(song);
    beast_composer_inputs::validate_inputs(result);
    result
}

/// Generalized channel picker: candidate roles are actual canon/countersubject
/// voices plus drums. Written policy is distinct from any future staff controls.
fn recipe_pick(
    sums: Span<u64>,
    counts: Span<u64>,
    voices: u32,
    countersubject: bool,
    count: u32,
    policy: beast_composer_inputs::ChannelPolicy,
) -> Array<u32> {
    use beast_composer_inputs::ChannelPolicy;
    let mut low: u32 = 0;
    let mut v = 1;
    while v < voices {
        if *counts.at(v) > 0 && mean_less(sums, counts, v, low) {
            low = v;
        }
        v += 1;
    }
    let mut order = array![0_u32];
    if low != 0 {
        order.append(low);
    }
    let mut rest = array![];
    match policy {
        ChannelPolicy::Genesis => {
            rest.append(DRUMS);
            if countersubject {
                rest.append(voices);
            }
            let mut v = 1;
            while v < voices {
                if v != low {
                    rest.append(v);
                }
                v += 1;
            }
        },
        ChannelPolicy::Seeded(seed) => {
            let mut v = 1;
            while v < voices {
                if v != low {
                    rest.append(v);
                }
                v += 1;
            }
            if countersubject {
                rest.append(voices);
            }
            rest.append(DRUMS);
            let mut values: Felt252Dict<u32> = Default::default();
            let n = rest.len();
            let mut i = 0;
            for value in rest.span() {
                values.insert(i.into(), *value);
                i += 1;
            }
            let mut h: u256 = poseidon_hash_span(array!['BEAST_CHANNEL_ORDER', seed].span()).into();
            let mut i = n - 1;
            while i > 0 {
                let j: u32 = (h % (i + 1).into()).try_into().unwrap();
                let a = values.get(i.into());
                let b = values.get(j.into());
                values.insert(i.into(), b);
                values.insert(j.into(), a);
                h /= 7;
                i -= 1;
            }
            rest = array![];
            let mut i = 0;
            while i < n {
                rest.append(values.get(i.into()));
                i += 1;
            }
        },
    }
    order.append_span(rest.span());
    let mut picked = array![];
    let mut i = 0;
    while i < count {
        picked.append(*order.at(i));
        i += 1;
    }
    picked
}

/// Complete written musical inputs, consumed directly. No Beast reconstruction,
/// Genesis shortcut, live counters, clock reads or implicit variation seed.
pub fn recipe_byte_array(x: beast_composer_inputs::SongInputs, mega: bool) -> ByteArray {
    render_recipe(x, mega, Option::None)
}

pub fn staff_recipe_byte_array(
    x: beast_composer_inputs::SongInputs,
    mega: bool,
    staff: crate::composition::evolution::StaffControls,
) -> ByteArray {
    render_recipe(x, mega, Option::Some(staff))
}

fn render_recipe(
    x: beast_composer_inputs::SongInputs,
    mega: bool,
    staff: Option<crate::composition::evolution::StaffControls>,
) -> ByteArray {
    use beast_composer_inputs::SpecialArrangement;
    beast_composer_inputs::validate_song(x);
    let score = crate::composition::beast_v11::build_v11_score_from_inputs(x);
    let p = score.params;
    let runs = voice_runs(score.events.span());
    let (sums, counts) = voice_stats(runs.span(), MAX_VOICES - 1);
    let roles = p.voice_count + if p.use_countersubject {
        1
    } else {
        0
    } + 1;
    // Determine the entire written priority order before current-staff note
    // changes. Each eligible extra index is fixed for this immutable recipe.
    let priority = recipe_pick(
        sums.span(),
        counts.span(),
        p.voice_count,
        p.use_countersubject,
        roles,
        x.arrangement.channel_policy,
    );
    let mut picked = array![];
    let mut i: u32 = 0;
    for role in priority.span() {
        let base_count: u32 = x.arrangement.channel_count.into();
        let include = if i < base_count {
            true
        } else {
            match staff {
                Option::Some(c) => crate::composition::evolution::extra_role_unlocked(
                    c.unlocked_extra_mask, i - base_count,
                ),
                Option::None => false,
            }
        };
        if include {
            picked.append(*role);
        }
        i += 1;
    }
    let mut events = if x.arrangement.weak_ties {
        tie_repeats(
            score.events.span(),
            runs.span(),
            picked.span(),
            sums.span(),
            counts.span(),
            score.section_ticks,
        )
    } else {
        let mut kept = array![];
        for e in score.events.span() {
            if contains(picked.span(), e.voice_id) {
                kept.append(*e);
            }
        }
        kept
    };
    let mut tempo_us = p.tempo_us;
    if let Option::Some(c) = staff {
        events =
            crate::composition::evolution::perform_staff_events(
                events.span(), p.velocity_ceiling, c,
            );
        let nudged = crate::composition::drift::nudge_tempo(tempo_us, c.tempo_delta);
        tempo_us =
            if nudged > beast_composer_inputs::MAX_TEMPO_US {
                beast_composer_inputs::MAX_TEMPO_US
            } else {
                nudged
            };
    }
    let yeti = match x.arrangement.special {
        SpecialArrangement::None => false,
        SpecialArrangement::Yeti(name) => {
            let (prefix, suffix): (u8, u8) = if name == 0 {
                (0, 0)
            } else {
                let n = name - 1;
                ((n / 18 + 1).try_into().unwrap(), (n % 18 + 1).try_into().unwrap())
            };
            let key = yeti_key(p.tonic_keynum, p.mode_id, named_mode_scale(p.mode_id));
            // Profile hashing is 32-bit; reduce before existing u64 multiplications
            // so the public u64 musical identity cannot overflow those helpers.
            let ornament_id = p.species_id % 0x100000000;
            events =
                yeti_ornaments(
                    events.span(),
                    score.section_ticks,
                    key,
                    p.ornament_density,
                    ornament_id,
                    prefix,
                    suffix,
                );
            events =
                yeti_avalanche(
                    events.span(), score.section_ticks, p.section_count.into(), p.tonic_keynum, key,
                );
            true
        },
    };
    let form = BeastForm {
        events,
        score_hash: 0,
        section_count: p.section_count,
        length_ticks: p.section_count.into() * score.section_ticks,
    };
    let tracks = beast_form_to_full_tracks_arranged(
        @form,
        tempo_us,
        p.tier,
        Option::Some(
            Voicing {
                beast_type: x.arrangement.family,
                species_id: p.species_id,
                name_variant_id: p.name_variant_id,
                voice_count: p.voice_count,
                use_countersubject: p.use_countersubject,
            },
        ),
        mega,
        ((p.species_id % 2 + (p.name_variant_id % 2).into()) % 2).try_into().unwrap(),
        Arrangement {
            top_lead: x.arrangement.top_lead,
            balanced: x.arrangement.balanced,
            drums: contains(picked.span(), DRUMS),
            rock: yeti,
            extra: if yeti {
                Option::Some((YETI_AVALANCHE_VOICE, YETI_AVALANCHE_PROGRAM))
            } else {
                Option::None
            },
            programs: Option::None,
        },
    );
    smf_byte_array(SMF_FORMAT, SMF_DIVISION, tracks.span())
}
