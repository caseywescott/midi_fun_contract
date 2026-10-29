//! Tables of the Monthly Track Editions engine (editions.cairo), generated from
//! offchain/beast-sound/src/editions.js by offchain/beast-sound/onchain/editions_cairo.mjs. Do not
//! edit:
//! change the source and rerun the generator.

/// Species 1..75: tonic pitch class (bits 0-3), then the first 8 Genesis theme degrees + 8
/// (4 bits each, from bit 4).
pub const SPECIES: [u64; 75] = [
    0x78a898680, 0xabdca8a81, 0x864687982, 0xa86565683, 0xcbacbca84, 0x9acb98a85, 0x675356786,
    0xedbca8987, 0xa9acdb988, 0xa86787689, 0xbdb97568a, 0xacdfeca8b, 0xdfdca9a80, 0x679bdba81,
    0xa87879782, 0x789a87683, 0xab9878684, 0x753579785, 0x9acb98a86, 0xdfdca9a87, 0xcefdeca88,
    0x89898a989, 0x54356798a, 0xedcba978b, 0x7979a8980, 0xa979a8a81, 0x568acb982, 0x545767683,
    0x134535784, 0x578679a85, 0x646465686, 0xb989a8a87, 0x134354688, 0xabdca8689, 0x764689a8a,
    0x9a978a98b, 0x676754680, 0x689baca81, 0xedecaba83, 0x979ba8a82, 0xcb9878684, 0x79bcab985,
    0x9acaca986, 0x8a9897687, 0xca8979a88, 0x8a8a9b989, 0x87976868a, 0x579a9868b, 0x9b9a98680,
    0xcecedb981, 0x4678a8782, 0xdfecb9a83, 0xdcb987984, 0x864346785, 0x79bacb986, 0xb98aca987,
    0xcedcaca88, 0x867575789, 0x578a8798a, 0xdbdca8a8b, 0x356578780, 0x435464681, 0x3579aca82,
    0xbcb9a8a83, 0xa868a8a84, 0xcbaca9785, 0xbdcb9ba86, 0xfdcbca987, 0x9bca9a988, 0x456898780,
    0x987568981, 0x989a86782, 0x756424683, 0xbcdca8984, 0x353575785,
];

/// Scales by id: ionian, dorian, phrygian, lydian, mixolydian, aeolian, harmonic, phrygdom,
/// locrian.
pub const SCALES: [[i32; 7]; 9] = [
    [0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 9, 10], [0, 1, 3, 5, 7, 8, 10], [0, 2, 4, 6, 7, 9, 11],
    [0, 2, 4, 5, 7, 9, 10], [0, 2, 3, 5, 7, 8, 10], [0, 2, 3, 5, 7, 8, 11], [0, 1, 4, 5, 7, 8, 10],
    [0, 1, 3, 5, 6, 8, 10],
];

/// Chord qualities by id: M m o + 7 m7 M7 mM7 ø7 o7 sus (tones over the root; three-tone ones pad
/// with 0).
pub const QUAL_TONES: [[i32; 4]; 11] = [
    [0, 4, 7, 0], [0, 3, 7, 0], [0, 3, 6, 0], [0, 4, 8, 0], [0, 4, 7, 10], [0, 3, 7, 10],
    [0, 4, 7, 11], [0, 3, 7, 11], [0, 3, 6, 10], [0, 3, 6, 9], [0, 5, 7, 0],
];
pub const QUAL_LEN: [u32; 11] = [3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 3];

/// Grammars by id: pop, romantic, minor, harmonic, dorian, mixo, mediant, andalusian, lydian,
/// blues, jazzy, hymn, hymnminor, battle, dirge. A chord is root * 16 + quality.
pub fn grammar_scale(g: u8) -> u8 {
    *[0, 0, 5, 6, 1, 4, 0, 7, 3, 4, 0, 0, 6, 5, 2].span().at(g.into())
}
pub fn grammar_twelve(g: u8) -> bool {
    g == 9
}
pub fn grammar_progs(g: u8) -> Span<Span<u8>> {
    match g {
        0 => [
            [0, 112, 145, 80].span(), [0, 145, 80, 112].span(), [145, 80, 0, 112].span(),
            [0, 80, 145, 112].span(), [0, 112, 80, 112].span(), [80, 0, 112, 145].span(),
        ]
            .span(),
        1 => [
            [0, 145, 37, 116].span(), [0, 80, 33, 116].span(), [0, 145, 80, 116].span(),
            [0, 68, 145, 80].span(), [37, 116, 0, 145].span(), [0, 65, 80, 116].span(),
        ]
            .span(),
        2 => [
            [1, 160, 128, 160].span(), [1, 81, 160, 48].span(), [1, 128, 48, 160].span(),
            [1, 128, 81, 112].span(), [1, 81, 113, 1].span(),
        ]
            .span(),
        3 => [
            [1, 81, 116, 1].span(), [1, 128, 81, 116].span(), [1, 81, 128, 112].span(),
            [81, 1, 116, 1].span(),
        ]
            .span(),
        4 => [
            [1, 80, 1, 80].span(), [1, 160, 80, 1].span(), [1, 80, 160, 1].span(),
            [1, 33, 48, 80].span(),
        ]
            .span(),
        5 => [
            [0, 160, 80, 0].span(), [0, 160, 128, 160].span(), [0, 80, 160, 80].span(),
            [0, 113, 80, 0].span(),
        ]
            .span(),
        6 => [
            [0, 128, 160, 0].span(), [0, 145, 80, 112].span(), [0, 80, 128, 160].span(),
            [0, 65, 80, 112].span(), [145, 80, 0, 112].span(),
        ]
            .span(),
        7 => [[1, 160, 128, 112].span(), [1, 81, 112, 1].span(), [1, 128, 160, 1].span()].span(),
        8 => [[0, 32, 0, 32].span(), [80, 0, 32, 0].span(), [0, 32, 145, 80].span()].span(),
        9 => [
            [4, 84, 4, 4, 84, 84, 4, 4, 116, 84, 4, 116].span(),
            [4, 84, 4, 4, 84, 84, 4, 36, 116, 84, 4, 116].span(),
        ]
            .span(),
        10 => [
            [6, 149, 37, 116].span(), [37, 116, 6, 6].span(), [6, 86, 69, 149].span(),
            [6, 37, 69, 86].span(),
        ]
            .span(),
        11 => [
            [0, 80, 112, 0].span(), [0, 145, 80, 112].span(), [0, 33, 112, 0].span(),
            [80, 0, 33, 112].span(), [0, 112, 145, 65].span(), [145, 80, 0, 112].span(),
        ]
            .span(),
        12 => [
            [1, 81, 112, 1].span(), [1, 128, 81, 112].span(), [128, 81, 112, 1].span(),
            [1, 160, 128, 112].span(),
        ]
            .span(),
        13 => [
            [1, 128, 160, 1].span(), [1, 128, 81, 112].span(), [1, 160, 128, 112].span(),
            [1, 81, 128, 112].span(), [1, 16, 1, 16].span(),
        ]
            .span(),
        _ => [
            [1, 16, 1, 1].span(), [1, 81, 1, 16].span(), [1, 128, 81, 1].span(),
            [1, 81, 160, 1].span(),
        ]
            .span(),
    }
}

/// Engines by id: waltz, chorale, groove, anthem, phase, song, variations, lullaby, blues, bossa,
/// dirge, battle, march (canon, edition 0, is not here).
pub const ENGINE_COUNT: u32 = 13;
/// The curated editions' engines (edition 0, the canon, is 255).
pub const CURATED: [u8; 13] = [255, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11];
#[derive(Copy, Drop)]
pub struct EngineDef {
    pub num: u32,
    pub den: u32,
    pub bpm_lo: u32,
    pub bpm_hi: u32,
    pub grammars: Span<u8>,
    pub forms: Span<Span<u8>>,
    pub accomp: Span<u8>,
    pub bass: Span<u8>,
    pub drums: Span<u8>,
    pub feel: u8,
    pub counter: u8,
    /// chords per bar (2: half-bar chords) and bars per chord (1 or 2)
    pub per_bar: u32,
    pub chord_bars: u32,
    pub swing: bool,
    /// [lead, counter, accomp, bass, pad] x [Magic, Hunter, Brute]
    pub palette: Span<u8>,
}
pub fn engine_def(e: u8) -> EngineDef {
    match e {
        0 => EngineDef {
            num: 3,
            den: 4,
            bpm_lo: 140,
            bpm_hi: 170,
            grammars: [1, 3, 2].span(),
            forms: [[0, 0, 1, 0].span(), [0, 1, 0, 1].span(), [0, 0, 1, 1].span()].span(),
            accomp: [3].span(),
            bass: [2].span(),
            drums: [6, 0].span(),
            feel: 6,
            counter: 1,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [0, 70, 64, 15, 44, 13, 17, 18, 99, 20, 27, 24, 33, 75, 32].span(),
        },
        1 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 66,
            bpm_hi: 84,
            grammars: [11, 12, 1].span(),
            forms: [[0, 0, 1, 0].span(), [0, 1, 0, 1].span()].span(),
            accomp: [11].span(),
            bass: [10].span(),
            drums: [0].span(),
            feel: 4,
            counter: 0,
            per_bar: 2,
            chord_bars: 1,
            swing: false,
            palette: [95, 43, 47, 95, 43, 47, 95, 43, 47, 95, 43, 47, 33, 31, 29].span(),
        },
        2 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 108,
            bpm_hi: 126,
            grammars: [4, 5, 2].span(),
            forms: [[0, 0, 1, 0].span(), [0, 1, 0, 1].span(), [0, 0, 1].span()].span(),
            accomp: [2, 1].span(),
            bass: [9].span(),
            drums: [1, 2].span(),
            feel: 3,
            counter: 0,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [59, 1, 84, 94, 66, 5, 66, 14, 94, 61, 79, 88, 28, 30, 29].span(),
        },
        3 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 150,
            bpm_hi: 172,
            grammars: [6, 0, 5].span(),
            forms: [[0, 1, 0, 1].span(), [0, 0, 1, 0].span(), [0, 0, 1, 1].span()].span(),
            accomp: [5].span(),
            bass: [3].span(),
            drums: [3, 1].span(),
            feel: 1,
            counter: 2,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [53, 62, 4, 76, 82, 77, 34, 80, 35, 21, 22, 23, 31, 90, 30].span(),
        },
        4 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 112,
            bpm_hi: 132,
            grammars: [8, 4, 0].span(),
            forms: [[0, 0, 1, 1].span(), [0, 1, 0, 1].span()].span(),
            accomp: [12].span(),
            bass: [5].span(),
            drums: [11, 0].span(),
            feel: 4,
            counter: 4,
            per_bar: 1,
            chord_bars: 2,
            swing: false,
            palette: [97, 45, 78, 17, 99, 44, 97, 74, 19, 27, 20, 26, 75, 33, 32].span(),
        },
        5 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 84,
            bpm_hi: 100,
            grammars: [0, 2, 5].span(),
            forms: [[3, 2, 3, 2].span(), [3, 3, 2, 2].span()].span(),
            accomp: [1, 0].span(),
            bass: [1].span(),
            drums: [2, 1].span(),
            feel: 2,
            counter: 1,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [42, 68, 89, 7, 0, 6, 18, 46, 17, 26, 93, 25, 32, 54, 90].span(),
        },
        6 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 96,
            bpm_hi: 112,
            grammars: [11, 1, 0].span(),
            forms: [[9, 3].span()].span(),
            accomp: [6].span(),
            bass: [0].span(),
            drums: [0].span(),
            feel: 0,
            counter: 1,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [52, 69, 3, 13, 15, 12, 18, 46, 17, 20, 24, 22, 33, 31, 29].span(),
        },
        7 => EngineDef {
            num: 6,
            den: 8,
            bpm_lo: 84,
            bpm_hi: 100,
            grammars: [0, 8, 1, 2].span(),
            forms: [[0, 0, 1, 0].span(), [0, 1, 0, 1].span()].span(),
            accomp: [7].span(),
            bass: [7].span(),
            drums: [0].span(),
            feel: 7,
            counter: 1,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [45, 78, 17, 33, 0, 70, 17, 44, 99, 20, 27, 20, 33, 75, 32].span(),
        },
        8 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 100,
            bpm_hi: 124,
            grammars: [9].span(),
            forms: [[0, 0, 0].span(), [0, 0].span()].span(),
            accomp: [8].span(),
            bass: [4].span(),
            drums: [4].span(),
            feel: 3,
            counter: 3,
            per_bar: 1,
            chord_bars: 1,
            swing: true,
            palette: [96, 51, 84, 46, 18, 66, 46, 18, 66, 93, 26, 79, 43, 95, 29].span(),
        },
        9 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 128,
            bpm_hi: 144,
            grammars: [10].span(),
            forms: [[0, 0, 1, 0].span(), [0, 1, 0, 1].span()].span(),
            accomp: [9].span(),
            bass: [6].span(),
            drums: [7].span(),
            feel: 0,
            counter: 1,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [70, 42, 98, 0, 7, 64, 46, 17, 99, 26, 27, 93, 32, 75, 54].span(),
        },
        10 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 120,
            bpm_hi: 144,
            grammars: [14, 7, 3].span(),
            forms: [[0, 0, 1, 0].span(), [0, 1, 0, 1].span()].span(),
            accomp: [10].span(),
            bass: [8].span(),
            drums: [8].span(),
            feel: 4,
            counter: 1,
            per_bar: 1,
            chord_bars: 2,
            swing: false,
            palette: [64, 72, 62, 8, 9, 6, 44, 71, 19, 86, 85, 88, 29, 30, 28].span(),
        },
        11 => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 150,
            bpm_hi: 172,
            grammars: [13, 3].span(),
            forms: [[9, 0, 1, 0, 9].span()].span(),
            accomp: [2].span(),
            bass: [9].span(),
            drums: [9].span(),
            feel: 1,
            counter: 0,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [62, 82, 96, 76, 77, 89, 94, 81, 66, 61, 79, 88, 91, 41, 91].span(),
        },
        _ => EngineDef {
            num: 4,
            den: 4,
            bpm_lo: 112,
            bpm_hi: 124,
            grammars: [0, 1, 3].span(),
            forms: [[0, 0, 1, 1].span(), [0, 1, 0, 1].span()].span(),
            accomp: [4].span(),
            bass: [1].span(),
            drums: [5].span(),
            feel: 5,
            counter: 2,
            per_bar: 1,
            chord_bars: 1,
            swing: false,
            palette: [47, 81, 53, 5, 3, 2, 94, 14, 16, 24, 22, 58, 29, 28, 30].span(),
        },
    }
}

/// Role pools for procedural editions: lead, counter, accomp, bass, pad.
pub fn pool(role: u32) -> Span<u8> {
    match role {
        0 => [
            0, 1, 2, 3, 4, 7, 8, 9, 42, 51, 52, 53, 59, 62, 64, 68, 69, 70, 73, 76, 77, 82, 89, 96,
            98,
        ]
            .span(),
        1 => [5, 6, 7, 12, 13, 15, 17, 44, 45, 63, 67, 74, 97, 99].span(),
        2 => [12, 14, 16, 17, 18, 19, 44, 46, 71, 74, 97, 99].span(),
        3 => [20, 21, 22, 23, 24, 25, 26, 27, 58, 61, 79, 85, 88, 93].span(),
        _ => [28, 29, 30, 31, 32, 33, 54, 75, 90].span(),
    }
}
pub const ADJ_COUNT: u32 = 18;

/// Rhythm cells (eighths; negative = rest) by bar (6 or 8 eighths) and feel id: lyric, heroic,
/// vocal, call, slow, march, waltz, compound.
pub fn cells(six: bool, feel: u8) -> Span<Span<i32>> {
    if six {
        match feel {
            0 => [[4, 2].span(), [2, 2, 2].span(), [6].span(), [3, 1, 2].span()].span(),
            1 => [[4, 2].span(), [2, 2, 2].span(), [6].span(), [3, 1, 2].span()].span(),
            2 => [[4, 2].span(), [2, 2, 2].span(), [6].span(), [3, 1, 2].span()].span(),
            3 => [[4, 2].span(), [2, 2, 2].span(), [6].span(), [3, 1, 2].span()].span(),
            4 => [[6].span(), [3, 3].span(), [4, 2].span()].span(),
            5 => [[4, 2].span(), [2, 2, 2].span(), [6].span(), [3, 1, 2].span()].span(),
            6 => [
                [4, 2].span(), [2, 2, 2].span(), [6].span(), [3, 1, 2].span(), [2, 1, 1, 2].span(),
                [4, 1, 1].span(),
            ]
                .span(),
            _ => [
                [3, 3].span(), [2, 1, 3].span(), [3, 2, 1].span(), [1, 1, 1, 3].span(), [6].span(),
                [2, 1, 2, 1].span(),
            ]
                .span(),
        }
    } else {
        match feel {
            0 => [
                [4, 4].span(), [2, 2, 4].span(), [3, 1, 4].span(), [2, 2, 2, 2].span(),
                [6, 2].span(), [4, 2, 2].span(), [3, 1, 2, 2].span(),
            ]
                .span(),
            1 => [
                [3, 3, 2].span(), [2, 2, 4].span(), [6, 2].span(), [1, 1, 2, 4].span(),
                [3, 1, 2, 2].span(), [2, 1, 1, 4].span(), [3, 3, 1, 1].span(),
            ]
                .span(),
            2 => [
                [1, 1, 1, 1, 2, 2].span(), [2, 1, 1, 2, 2].span(), [1, 1, 2, 4].span(),
                [2, 2, 1, 1, -2].span(), [1, 1, 1, 1, 4].span(), [-2, 1, 1, 2, 2].span(),
            ]
                .span(),
            3 => [
                [2, 1, 1, -4].span(), [1, 1, 2, -4].span(), [3, 1, -4].span(),
                [-2, 1, 1, 1, 1, -2].span(), [1, 1, 1, 1, -4].span(),
            ]
                .span(),
            4 => [[8].span(), [4, 4].span(), [6, 2].span(), [4, 4].span()].span(),
            5 => [
                [2, 1, 1, 2, 2].span(), [3, 1, 2, 2].span(), [2, 2, 4].span(),
                [1, 1, 1, 1, 4].span(), [3, 1, 3, 1].span(),
            ]
                .span(),
            6 => [
                [4, 4].span(), [2, 2, 4].span(), [3, 1, 4].span(), [2, 2, 2, 2].span(),
                [6, 2].span(), [4, 2, 2].span(), [3, 1, 2, 2].span(),
            ]
                .span(),
            _ => [
                [4, 4].span(), [2, 2, 4].span(), [3, 1, 4].span(), [2, 2, 2, 2].span(),
                [6, 2].span(), [4, 2, 2].span(), [3, 1, 2, 2].span(),
            ]
                .span(),
        }
    }
}

/// Drum grooves by id: none, rock, halftime, drive, shuffle, march, waltz, bossa, dirge, battle,
/// battle16, minimal. (steps per bar, hits in the source's order as step | key << 8 | velocity <<
/// 16).
pub fn groove(g: u8) -> (u32, Span<u32>) {
    match g {
        0 => (1, [].span()),
        1 => (
            16,
            [
                5776384, 5776392, 5776394, 7349764, 7349772, 5777920, 5777922, 5777924, 5777926,
                5777928, 5777930, 5777932, 5777934,
            ]
                .span(),
        ),
        2 => (
            16,
            [
                5776384, 5776394, 7349768, 5777920, 5777922, 5777924, 5777926, 5777928, 5777930,
                5777932, 5777934,
            ]
                .span(),
        ),
        3 => (
            16,
            [
                7349248, 5776388, 7349256, 5776396, 7349764, 7349772, 3417615, 5777922, 5777926,
                5777930, 5777934, 5778946, 5778950, 5778954, 5778958,
            ]
                .span(),
        ),
        4 => (
            12,
            [
                5776384, 5776390, 7349763, 7349769, 5777920, 5777922, 5777923, 5777925, 5777926,
                5777928, 5777929, 5777931,
            ]
                .span(),
        ),
        5 => (
            16,
            [
                5776384, 5776392, 7349760, 3417602, 5776899, 7349764, 3417606, 5776904, 3417610,
                5776907, 7349772, 5776910, 3417615,
            ]
                .span(),
        ),
        6 => (12, [5776384, 5777924, 5777928].span()),
        7 => (
            16,
            [
                5776384, 5776387, 5776388, 5776391, 5776392, 5776395, 5776396, 5776399, 5777664,
                5777667, 5777670, 5777674, 5777677, 3418624, 3418625, 3418626, 3418627, 3418628,
                3418629, 3418630, 3418631, 3418632, 3418633, 3418634, 3418635, 3418636, 3418637,
                3418638, 3418639,
            ]
                .span(),
        ),
        8 => (16, [7349248, 5778184].span()),
        9 => (
            16,
            [
                5776384, 5776387, 5776390, 5776393, 5776396, 5776398, 7349764, 7349772, 5777920,
                5777922, 5777924, 5777926, 5777928, 5777930, 5777932, 5777934,
            ]
                .span(),
        ),
        10 => (
            16,
            [
                5776384, 5776387, 5776390, 5776393, 5776396, 5776398, 7349764, 7349772, 5777920,
                3418625, 5777922, 3418627, 5777924, 3418629, 5777926, 3418631, 5777928, 3418633,
                5777930, 3418635, 5777932, 3418637, 5777934, 3418639,
            ]
                .span(),
        ),
        _ => (16, [5776384, 5776392, 3418626, 3418630, 3418634, 3418638].span()),
    }
}

/// R() < p as raw < T (raw a 32-bit draw).
pub const P012: u64 = 515396076;
pub const P066: u64 = 2834678416;
pub const P090: u64 = 3865470567;
pub const P050: u64 = 2147483648;
pub const P030: u64 = 1288490189;

/// melody() contour: (A, B) such that prev < target - 2 <=> prev < A and prev > target + 2 <=>
/// prev > B, for the ranges the engines use (lo, hi) and phrase position pos / half.
pub fn contour_bounds(lo: i32, half: u32, pos: u32) -> (i32, i32) {
    if lo == 61 && half == 4 {
        *[(65, 68), (70, 73), (72, 75), (70, 73)].span().at(pos)
    } else if lo == 61 && half == 6 {
        *[(65, 68), (69, 72), (71, 74), (72, 75), (71, 74), (69, 72)].span().at(pos)
    } else if lo == 66 && half == 4 {
        *[(70, 73), (75, 78), (77, 80), (75, 78)].span().at(pos)
    } else if lo == 66 && half == 6 {
        *[(70, 73), (74, 77), (76, 79), (77, 80), (76, 79), (74, 77)].span().at(pos)
    } else if lo == 64 && half == 4 {
        *[(68, 71), (73, 76), (74, 78), (73, 76)].span().at(pos)
    } else if lo == 64 && half == 6 {
        *[(68, 71), (71, 74), (74, 77), (74, 78), (74, 77), (71, 74)].span().at(pos)
    } else if lo == 67 && half == 4 {
        *[(71, 74), (77, 80), (79, 82), (77, 80)].span().at(pos)
    } else if lo == 67 && half == 6 {
        *[(71, 74), (75, 78), (78, 81), (79, 82), (78, 81), (75, 78)].span().at(pos)
    } else {
        panic!("contour range")
    }
}
