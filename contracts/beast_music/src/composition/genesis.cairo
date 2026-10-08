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
use crate::composition::beast_score::BeastForm;
use crate::composition::beast_v11::{V11Override, build_v11_score_with};
use crate::composition::beast_v3_sound::{
    BeastV3LiveState, PackableBeastV3, map_v3_beast_to_composition_params,
};
use crate::composition::full_midi::{
    Arrangement, Voicing, beast_form_to_full_smf_bytes_arranged, mega_lead_pick,
};
use crate::composition::melodic_canon::NoteEvent;

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
fn genesis_mode(id: u64, mode_id: u8) -> u8 {
    if id == 33 {
        return 5;
    }
    mode_id
}

/// A mode's scale as named, semitones from the tonic (Locrian, harmonic minor and Dorian #4
/// included).
fn named_mode_scale(mode_id: u8) -> Option<Span<u8>> {
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
fn neutral_live() -> BeastV3LiveState {
    BeastV3LiveState {
        adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1,
    }
}

const DRUMS: u32 = 1000;
/// Voice ids the composer uses (four canon voices and the countersubject).
const MAX_VOICES: u32 = 5;

/// Pitch sum and note count per voice 0..MAX_VOICES, in one pass.
fn voice_stats(events: Span<NoteEvent>) -> (Array<u64>, Array<u64>) {
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
/// pitch statistics. Returns the kept events voice by voice, each chronological.
fn tie_repeats(
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
                        prev = Option::Some(NoteEvent { duration: p.duration + e.duration, ..p });
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

/// The Genesis Track MIDI (self-contained, for onchain-midi-player) of a Beast: its species' (after
/// the default swaps), with the mega arrangement when the Beast is shiny. Species past 75 compose
/// with their own tier and type and their own theme.
pub fn genesis_smf_bytes(beast: PackableBeastV3) -> Array<u8> {
    let src = genesis_swap(beast.id);
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
    let ov = V11Override {
        voice_count: Option::Some(4),
        section_count: Option::Some(tier_sections(tier)),
        mode_id: Option::Some(mode),
        tonic_keynum: Option::Some(ks.tonic_keynum),
        register_band: Option::Some(ks.register_band),
        ornament_density: Option::Some(pg.ornament_density),
        name_variant_id: Option::Some(0),
        use_countersubject: Option::Some(true),
        scale: named_mode_scale(mode),
        trill: Option::Some(false),
    };
    let score = build_v11_score_with(cb, live, ov);
    let p = score.params;
    // the Genesis channels, then ties in the inner voices (statistics of the full score: the kept
    // voices' are the same, since a channel is kept or dropped whole)
    let (sums, counts) = voice_stats(score.events.span());
    let picked = genesis_pick(sums.span(), counts.span(), genesis_channels(tier));
    let events = tie_repeats(
        score.events.span(), picked.span(), sums.span(), counts.span(), score.section_ticks,
    );
    let form = BeastForm {
        events,
        score_hash: 0,
        section_count: p.section_count,
        length_ticks: p.section_count.into() * score.section_ticks,
    };
    beast_form_to_full_smf_bytes_arranged(
        @form,
        p.tempo_us,
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
        Arrangement { top_lead: true, balanced: true, drums: contains(picked.span(), DRUMS) },
    )
}

/// The same, packed 31 bytes per felt after the byte length.
pub fn genesis_midi(beast: PackableBeastV3) -> Array<felt252> {
    midi::pack::to_felt252_array(genesis_smf_bytes(beast).span())
}
