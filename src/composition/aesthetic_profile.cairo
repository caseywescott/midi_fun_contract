//! Aesthetic Profiles — the parameterized vertical-acceptability layer.
//!
//! The Renaissance canon engine (`canon_rules` / `melodic_canon`) guarantees correctness *by
//! construction* through one binary question per vertical: `is_consonant_class(generic_class(a,b))`
//! on the diatonic (mod-7) lattice. That question is the *only* thing that ties the engine to a
//! single style. This module turns it into a **parameter**: an [`AestheticProfile`] supplies
//!
//!   * a **lattice** (`octave` = 7 diatonic, or 12 chromatic — quality-aware),
//!   * a **graded tension table** (one tier per interval class), and
//!   * **policies** (parallel-perfect handling, avoid-note handling).
//!
//! Every other part of the engine (the lag-difference identity, the leader walk, the followers,
//! the validators) is reused verbatim; only the class function and the acceptability predicate are
//! swapped in. Profiles are *separately accessible and non-conflicting*: a profile is just a value,
//! and the same generalized functions below derive the permitted-leader alphabet for any of them
//! without search.
//!
//! See `docs/extended_harmony_canon_spec.md`.

use core::array::ArrayTrait;
use koji::composition::canon_rules::{abs_i32, intersect_steps, keep_within_skip, PairConstraint};

// ──────────────────────────────────────────────────────────
// Tension tiers (higher = more tension). The walker forbids verticals whose tier exceeds the
// profile's `max_tier`; everything at or below is allowed (that is how color tones get in).
// ──────────────────────────────────────────────────────────

pub const STABLE: u8 = 0; // unison/octave, perfect fifth
pub const CONSONANT: u8 = 1; // thirds, sixths (and P4 where it is a consonance)
pub const COLOR: u8 = 2; // usable extension color (7ths, 9ths, quartal stacks)
pub const SOFT: u8 = 3; // soft dissonance / tritone color
pub const CLASH: u8 = 4; // the hard gate: minor 2nd / minor 9th half-step collision

// Parallel-perfect policy.
pub const PAR_FORBID: u8 = 0; // never repeat a step that yields a perfect interval
pub const PAR_LIMIT: u8 = 1; // discourage chains (treated like forbid-immediate-repeat)
pub const PAR_ALLOW: u8 = 2; // planing / quartal: parallels are the idiom

// Avoid-note (chord-scale) policy.
pub const AVOID_NONE: u8 = 0;
pub const AVOID_STRONG: u8 = 1; // avoid notes barred on strong beats, ok as passing tones
pub const AVOID_ALWAYS: u8 = 2;

// Lattice octave sizes.
pub const OCT_DIATONIC: u32 = 7;
pub const OCT_CHROMATIC: u32 = 12;

/// Profile id for Renaissance counterpoint that must remain valid under octave inversion.
pub const PROFILE_RENAISSANCE_INVERTIBLE_ID: u32 = 25;

// ──────────────────────────────────────────────────────────
// The profile
// ──────────────────────────────────────────────────────────

/// A complete aesthetic regime. `table` has exactly `octave` entries; entry `c` is the tension
/// tier of interval class `c` (`abs(distance) % octave`). Keeping the chromatic table *directed*
/// in `0..11` (not folded to `0..6`) is what distinguishes a major 7th (class 11 = color) from a
/// minor 2nd / minor 9th (class 1 = clash) — the crux of extended-harmony correctness.
#[derive(Copy, Drop)]
pub struct AestheticProfile {
    pub id: u32,
    pub name: felt252,
    pub octave: u32,
    pub table: Span<u8>,
    pub max_tier: u8,
    pub par_policy: u8,
    pub avoid_policy: u8,
}

// ──────────────────────────────────────────────────────────
// Profile catalogue
// ──────────────────────────────────────────────────────────

/// Profile 0 — Renaissance. Reproduces `is_consonant_class` exactly: on the mod-7 lattice the
/// consonances are unison/octave (0), 3rd (2), 5th (4), 6th (5); the 2nd/4th/7th are clashes.
pub fn profile_renaissance() -> AestheticProfile {
    AestheticProfile {
        id: 0,
        name: 'renaissance',
        octave: OCT_DIATONIC,
        //         0      1      2          3      4       5          6
        table: array![STABLE, CLASH, CONSONANT, CLASH, STABLE, CONSONANT, CLASH].span(),
        max_tier: CONSONANT,
        par_policy: PAR_FORBID,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 25 — Renaissance, invertible at the octave. Same consonance budget as Profile 0,
/// except the perfect fifth is a hard clash because it inverts to a dissonant fourth.
pub fn profile_renaissance_invertible() -> AestheticProfile {
    AestheticProfile {
        id: PROFILE_RENAISSANCE_INVERTIBLE_ID,
        name: 'ren_ic_oct',
        octave: OCT_DIATONIC,
        //         0      1      2          3      4      5          6
        table: array![STABLE, CLASH, CONSONANT, CLASH, CLASH, CONSONANT, CLASH].span(),
        max_tier: CONSONANT,
        par_policy: PAR_FORBID,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 1 — Extended-Tertian / Jazz. Chromatic, graded; the only hard gate is the m2/m9 clash.
/// Major 7ths (11) and m7 (10) are color; the tritone (6) is soft; thirds/sixths consonant.
pub fn profile_jazz() -> AestheticProfile {
    AestheticProfile {
        id: 1,
        name: 'jazz',
        octave: OCT_CHROMATIC,
        //         0     1     2     3      4      5     6    7     8      9      10    11
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_STRONG,
    }
}

/// Profile 2 — Quartal (Persichetti). The perfect fourth (5) and fifth (7) are the *stable*
/// intervals; seconds/sevenths are tension; m2 remains the only clash. Parallels are the idiom.
pub fn profile_quartal() -> AestheticProfile {
    AestheticProfile {
        id: 2,
        name: 'quartal',
        octave: OCT_CHROMATIC,
        //         0     1     2     3      4      5      6    7     8      9      10    11
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, STABLE, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, SOFT,
        ]
            .span(),
        max_tier: COLOR,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 3 — Impressionist planing (Debussy / Ravel). Same color grading as jazz, but parallel
/// perfects are *required* (a whole chord shape moves in parallel), and no avoid-note filtering.
pub fn profile_planing() -> AestheticProfile {
    AestheticProfile {
        id: 3,
        name: 'planing',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 4 — Hindemith graded tension (Series 2). Tiers follow the increasing-tension ordering
/// octave < P5 < P4 < M3/m6 < m3/M6 < M2/m7 < m2/M7 < tritone. The m2/m9 collision is still gated
/// as the clash; everything else is permitted (dissonance is shaped, not banned).
pub fn profile_hindemith() -> AestheticProfile {
    AestheticProfile {
        id: 4,
        name: 'hindemith',
        octave: OCT_CHROMATIC,
        //         0     1     2     3      4       5         6    7     8         9     10    11
        table: array![
            STABLE, CLASH, COLOR, COLOR, CONSONANT, CONSONANT, SOFT, STABLE, CONSONANT, COLOR,
            COLOR, SOFT,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 5 — Ligeti "White on White" (diatonic micropolyphony). The deliberate inverse of
/// Renaissance on the *same* mod-7 white-key lattice: the soft diatonic cluster IS the aesthetic,
/// so 2nds and 7ths are graded as color and *nothing* is a clash. Parallels are embraced (the
/// étude's canon is at the octave; voice independence is not the goal — band color is). The grading
/// is retained, not flattened, so the band/contour machinery still has tiers to steer by.
///
/// This is the conceptual counterweight to the extended-harmony spec's "the one clash is the m2":
/// in a slow, tender, white-key frame even the diatonic half-step (E–F, B–C) reads as color, not
/// collision. Context — not interval — decides, and here the context forbids nothing.
pub fn profile_ligeti_white() -> AestheticProfile {
    AestheticProfile {
        id: 5,
        name: 'ligeti_white',
        octave: OCT_DIATONIC,
        //         0      1      2          3     4       5          6
        table: array![STABLE, COLOR, CONSONANT, SOFT, STABLE, CONSONANT, COLOR].span(),
        max_tier: SOFT, // every diatonic vertical passes; tiers remain for contour steering
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 6 — Ligeti chromatic micropolyphony (Lux Aeterna / Atmosphères). The radical sibling of
/// Profile 5: on the chromatic lattice it *un-gates the m2/m9* (class 1 → SOFT, not CLASH), because
/// the dense chromatic cluster band — half-steps and all — is precisely the wanted sonority. This
/// intentionally breaks the extended-harmony spec's central rule; correctness-by-construction still
/// holds because the profile simply rejects nothing (`max_tier` admits every class). Use it only
/// when the cluster *is* the music; `no_minor_ninth` will (correctly) be false here.
pub fn profile_ligeti_micropolyphony() -> AestheticProfile {
    AestheticProfile {
        id: 6,
        name: 'ligeti_micro',
        octave: OCT_CHROMATIC,
        //         0     1     2      3          4          5      6     7       8          9
        //         10    11
        table: array![
            STABLE, SOFT, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, SOFT,
        ]
            .span(),
        max_tier: SOFT, // admits every class, including the embraced half-step (class 1)
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 7 — Lydian major-ninth. A jazz-family profile whose default macroharmony wants the
/// bright Imaj9/#11 sonority: M7 and 9ths are color, the tritone is soft Lydian color, and the
/// avoid-note policy keeps the natural 11 off strong structural beats.
pub fn profile_lydian_maj9() -> AestheticProfile {
    AestheticProfile {
        id: 7,
        name: 'lydian_maj9',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_STRONG,
    }
}

/// Profile 8 — Dominant altered. The dominant-function exception: class 1 is admitted as color so
/// a b9 can be part of the sonority. This intentionally relaxes the generic extended-harmony
/// "minor ninth is a clash" rule, but only for configs that explicitly opt into this profile.
pub fn profile_dominant_altered() -> AestheticProfile {
    AestheticProfile {
        id: 8,
        name: 'dom_alt',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, COLOR, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, COLOR,
            COLOR, COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 9 — Whole-tone planing. Odd semitone classes are rejected so the walk stays inside a
/// whole-tone color field; parallel motion is the point, not a counterpoint error.
pub fn profile_whole_tone_planing() -> AestheticProfile {
    AestheticProfile {
        id: 9,
        name: 'whole_tone',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, CONSONANT, CLASH, CONSONANT, CLASH, SOFT, CLASH, CONSONANT, CLASH,
            COLOR, CLASH,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 10 — Octatonic / Stravinsky. Symmetric minor-thirds and tritones are embraced, while
/// sustained half-step collisions remain gated.
pub fn profile_octatonic_stravinsky() -> AestheticProfile {
    AestheticProfile {
        id: 10,
        name: 'octatonic',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, COLOR, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR,
            COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 11 — Suspended quartal. Fourths, fifths and suspended seconds carry the identity;
/// thirds are tolerated as color rather than allowed to dominate the vertical vocabulary.
pub fn profile_sus_quartal() -> AestheticProfile {
    AestheticProfile {
        id: 11,
        name: 'sus_quartal',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, CONSONANT, COLOR, COLOR, STABLE, SOFT, STABLE, COLOR, CONSONANT, COLOR,
            COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 12 — Minimalist pandiatonic. Same white-key lattice as Renaissance, but all diatonic
/// verticals are allowed as modal color; this is a Reich/Glass-like consonant field, not species
/// counterpoint.
pub fn profile_minimalist_pandiatonic() -> AestheticProfile {
    AestheticProfile {
        id: 12,
        name: 'pandiatonic',
        octave: OCT_DIATONIC,
        table: array![STABLE, COLOR, CONSONANT, COLOR, STABLE, CONSONANT, COLOR].span(),
        max_tier: COLOR,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 13 — Spectral series. Fifths and major thirds are the stable poles; whole-step and
/// seventh color is permitted, while the tritone and half-step stay outside the default budget.
pub fn profile_spectral_series() -> AestheticProfile {
    AestheticProfile {
        id: 13,
        name: 'spectral',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, STABLE, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR,
            SOFT,
        ]
            .span(),
        max_tier: COLOR,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 14 — Bartok axis. Tritone symmetry and minor-third axes are stable enough to steer by;
/// class-1 collisions are still rejected.
pub fn profile_bartok_axis() -> AestheticProfile {
    AestheticProfile {
        id: 14,
        name: 'bartok_axis',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, STABLE, COLOR, COLOR, STABLE, COLOR, COLOR, STABLE, COLOR, COLOR,
        ]
            .span(),
        max_tier: COLOR,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 15 — Soft cluster. A deliberately gentler cluster world: half-steps are admitted as
/// color, not fully normalized as in Ligeti-micro. Duration-aware "weak only" handling can be added
/// later; this table gives the catalogue a lighter cluster option today.
pub fn profile_cluster_soft() -> AestheticProfile {
    AestheticProfile {
        id: 15,
        name: 'cluster_soft',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, COLOR, CONSONANT, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT,
            CONSONANT, COLOR, COLOR,
        ]
            .span(),
        max_tier: COLOR,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 16 — Canon per tonos. A real-answer, intentionally modulating major-seventh world. It
/// keeps the jazz no-m2 gate but drops the key-anchored avoid-note filter so the accumulated
/// transposition is heard as the behavior, not corrected away.
pub fn profile_canon_per_tonos() -> AestheticProfile {
    AestheticProfile {
        id: 16,
        name: 'per_tonos',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 17 — Impressionist added-6/9 color. Warm triadic sonorities with sixths and ninths as
/// stable color, while sharper altered tensions stay soft-gated.
pub fn profile_impressionist_added6() -> AestheticProfile {
    AestheticProfile {
        id: 17,
        name: 'impr_add6',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR,
            COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 18 — Bitonal split-field. Maintains clear triadic anchors while tolerating selected
/// cross-relations as color instead of default clashes.
pub fn profile_bitonal_split() -> AestheticProfile {
    AestheticProfile {
        id: 18,
        name: 'bitonal',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, COLOR, COLOR, CONSONANT, STABLE, COLOR, SOFT, STABLE, CONSONANT, COLOR, COLOR,
            SOFT,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 19 — Phrygian-cadential gravity. Keeps semitone pull available as controlled color
/// while retaining a strict cap on denser clash combinations.
pub fn profile_phrygian_cadential() -> AestheticProfile {
    AestheticProfile {
        id: 19,
        name: 'phrygian',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, COLOR, CONSONANT, CONSONANT, COLOR, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR,
            COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_STRONG,
    }
}

/// Profile 20 — Pentatonic open-fifths. Promotes fifths/fourths/thirds and suppresses dense
/// semitone friction to keep an open, transparent field.
pub fn profile_pentatonic_open() -> AestheticProfile {
    AestheticProfile {
        id: 20,
        name: 'penta_open',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, STABLE, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, CLASH,
        ]
            .span(),
        max_tier: COLOR,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 21 — Neo-Riemannian triadic voice-leading. Triad classes are privileged and smooth
/// third-related shifts are encouraged without requiring strict diatonic anchoring.
pub fn profile_neo_riemannian() -> AestheticProfile {
    AestheticProfile {
        id: 21,
        name: 'neo_riem',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, STABLE, COLOR, SOFT, STABLE, STABLE, CONSONANT, COLOR,
            COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 22 — Pentatonic open-fifths (smooth). Same vertical budget as Profile 20, but the
/// leader walk forbids semitone melodic steps and ornaments stay on structural degrees only (no
/// chromatic `subdivide` fill between notes).
pub fn profile_pentatonic_open_smooth() -> AestheticProfile {
    AestheticProfile {
        id: 22,
        name: 'penta_smooth',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, STABLE, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, CLASH,
        ]
            .span(),
        max_tier: COLOR,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

/// Profile 24 — Jazz improvised canon. Same vertical budget as Profile 1, but the leader walk
/// follows a four-region I–vi–ii–V turnaround (chord-scale filtering per region), forbids
/// semitone structural steps, and keeps ornaments on structural degrees only.
pub fn profile_jazz_improv() -> AestheticProfile {
    AestheticProfile {
        id: 24,
        name: 'jazz_improv',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, CONSONANT, CONSONANT,
            COLOR, COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_LIMIT,
        avoid_policy: AVOID_STRONG,
    }
}

/// Profile 23 — Impressionist add6/9 (smooth). Same color grading as Profile 17, but the pitch
/// field removes adjacent semitone pairs (no {2,3,4} cluster) and melodic motion skips semitone
/// steps; ornaments do not chromatically fill intervals.
pub fn profile_impressionist_added6_smooth() -> AestheticProfile {
    AestheticProfile {
        id: 23,
        name: 'impr_smooth',
        octave: OCT_CHROMATIC,
        table: array![
            STABLE, CLASH, COLOR, CONSONANT, CONSONANT, COLOR, SOFT, STABLE, COLOR, CONSONANT, COLOR,
            COLOR,
        ]
            .span(),
        max_tier: SOFT,
        par_policy: PAR_ALLOW,
        avoid_policy: AVOID_NONE,
    }
}

pub fn num_profiles() -> u32 {
    26
}

pub fn profile_by_id(id: u32) -> AestheticProfile {
    if id == 1 {
        profile_jazz()
    } else if id == 2 {
        profile_quartal()
    } else if id == 3 {
        profile_planing()
    } else if id == 4 {
        profile_hindemith()
    } else if id == 5 {
        profile_ligeti_white()
    } else if id == 6 {
        profile_ligeti_micropolyphony()
    } else if id == 7 {
        profile_lydian_maj9()
    } else if id == 8 {
        profile_dominant_altered()
    } else if id == 9 {
        profile_whole_tone_planing()
    } else if id == 10 {
        profile_octatonic_stravinsky()
    } else if id == 11 {
        profile_sus_quartal()
    } else if id == 12 {
        profile_minimalist_pandiatonic()
    } else if id == 13 {
        profile_spectral_series()
    } else if id == 14 {
        profile_bartok_axis()
    } else if id == 15 {
        profile_cluster_soft()
    } else if id == 16 {
        profile_canon_per_tonos()
    } else if id == 17 {
        profile_impressionist_added6()
    } else if id == 18 {
        profile_bitonal_split()
    } else if id == 19 {
        profile_phrygian_cadential()
    } else if id == 20 {
        profile_pentatonic_open()
    } else if id == 21 {
        profile_neo_riemannian()
    } else if id == 22 {
        profile_pentatonic_open_smooth()
    } else if id == 23 {
        profile_impressionist_added6_smooth()
    } else if id == 24 {
        profile_jazz_improv()
    } else if id == PROFILE_RENAISSANCE_INVERTIBLE_ID {
        profile_renaissance_invertible()
    } else {
        profile_renaissance()
    }
}

// ──────────────────────────────────────────────────────────
// Generalized vertical predicate (replaces generic_class / is_consonant_class)
// ──────────────────────────────────────────────────────────

/// Unfolded distance class of the vertical between two lattice positions, in `0..octave-1`.
/// This uses absolute distance (not direction), but it does **not** fold chromatic complements:
/// m2 remains class 1 and M7 remains class 11, while m9 folds onto class 1.
pub fn unfolded_distance_class(profile: @AestheticProfile, a: i32, b: i32) -> u32 {
    abs_i32(a - b) % *profile.octave
}

/// Backward-compatible alias for the class function used throughout the canon engine.
pub fn vertical_class(profile: @AestheticProfile, a: i32, b: i32) -> u32 {
    unfolded_distance_class(profile, a, b)
}

pub fn vertical_tier(profile: @AestheticProfile, a: i32, b: i32) -> u8 {
    *(*profile.table).at(vertical_class(profile, a, b))
}

/// The single by-construction gate: a vertical is acceptable iff its tier is within budget.
pub fn vertical_ok(profile: @AestheticProfile, a: i32, b: i32) -> bool {
    vertical_tier(profile, a, b) <= *profile.max_tier
}

/// True iff the vertical is a *perfect* consonance (unison/octave, or perfect fifth) under this
/// lattice — used by the parallel-perfect avoidance rule.
pub fn is_perfect_vertical(profile: @AestheticProfile, a: i32, b: i32) -> bool {
    let cls = vertical_class(profile, a, b);
    let fifth: u32 = if *profile.octave == OCT_DIATONIC {
        4
    } else {
        7
    };
    cls == 0 || cls == fifth
}

// ──────────────────────────────────────────────────────────
// Generalized alphabet derivation (still closed-form, never a search)
// ──────────────────────────────────────────────────────────

/// Every melodic step in `[-octave, +octave]` for this lattice.
pub fn full_step_range_p(profile: @AestheticProfile) -> Array<i32> {
    let oct: i32 = (*profile.octave).try_into().unwrap();
    let mut out: Array<i32> = ArrayTrait::new();
    let mut m: i32 = -oct;
    loop {
        if m > oct {
            break;
        }
        out.append(m);
        m += 1;
    };
    out
}

/// Permitted leader steps for a single follower at interval of imitation `t` (lag 1):
/// the vertical contributed is `t - m`, kept iff `vertical_ok`.
pub fn allowed_leader_steps_p(profile: @AestheticProfile, t: i32) -> Array<i32> {
    let oct: i32 = (*profile.octave).try_into().unwrap();
    let mut out: Array<i32> = ArrayTrait::new();
    let mut m: i32 = -oct;
    loop {
        if m > oct {
            break;
        }
        if vertical_ok(profile, t, m) {
            out.append(m);
        }
        m += 1;
    };
    out
}

/// The permitted leader alphabet for a stacked canon: the intersection of every adjacent voice
/// pair's single-step alphabet. (Longer-window pairs are enforced during the walk.)
pub fn allowed_steps_multivoice_p(profile: @AestheticProfile, offsets: Span<i32>) -> Array<i32> {
    let mut acc: Array<i32> = full_step_range_p(profile);
    let n = offsets.len();
    let mut i: u32 = 0;
    loop {
        if i + 1 >= n {
            break;
        }
        let rel = *offsets.at(i + 1) - *offsets.at(i);
        acc = intersect_steps(acc.span(), allowed_leader_steps_p(profile, rel).span());
        i += 1;
    };
    acc
}

/// The improvisation-friendly bias set: alphabet steps no larger than `max_skip`.
pub fn stylistic_multivoice_p(
    profile: @AestheticProfile, offsets: Span<i32>, max_skip: u32,
) -> Array<i32> {
    keep_within_skip(allowed_steps_multivoice_p(profile, offsets).span(), max_skip)
}

/// Profile-aware windowed constraint check (generalizes `step_satisfies_constraints`): for every
/// pair whose window closes at this note, the cumulative leader span against the relative interval
/// must be an acceptable vertical under the profile. Fully local — no search, no backtracking.
pub fn step_satisfies_constraints_p(
    profile: @AestheticProfile, constraints: Span<PairConstraint>, prev_steps: Span<i32>, m: i32,
) -> bool {
    let pos = prev_steps.len() + 1;
    let mut c: u32 = 0;
    let mut ok = true;
    loop {
        if c >= constraints.len() {
            break;
        }
        let pc = *constraints.at(c);
        if pos >= pc.w {
            let mut windowsum: i32 = m;
            let mut t: u32 = 0;
            loop {
                if t + 1 >= pc.w {
                    break;
                }
                windowsum += *prev_steps.at(prev_steps.len() - 1 - t);
                t += 1;
            };
            if !vertical_ok(profile, pc.d, windowsum) {
                ok = false;
                break;
            }
        }
        c += 1;
    };
    ok
}

/// True if `pc` (a pitch class) is an avoid note for `chord_pcs`: it sits a half-step above some
/// chord tone (Levine). Caller supplies pitch classes in `0..11`.
pub fn is_avoid_note(chord_pcs: Span<u8>, pc: u8) -> bool {
    // pc is an avoid note if (pc - 1) mod 12 is a chord tone.
    let below: u8 = (pc + 11) % 12;
    contains_pc(chord_pcs, below)
}

fn contains_pc(set: Span<u8>, v: u8) -> bool {
    let mut i: u32 = 0;
    let mut found = false;
    loop {
        if i >= set.len() {
            break;
        }
        if *set.at(i) == v {
            found = true;
            break;
        }
        i += 1;
    };
    found
}
