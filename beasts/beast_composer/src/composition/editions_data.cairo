//! Tables of the Monthly Track Editions engine (editions.cairo), generated from
//! offchain/beast-sound/src/editions_lite.js by offchain/beast-sound/onchain/editions_cairo.mjs. Do
//! not edit: change the source and rerun the generator.

/// Species 1..75: tonic pitch class (bits 0-3), then the first 6 Genesis theme degrees + 8
/// (4 bits each, from bit 4), then the Sound Check preset (bits 28-30: an index into the
/// family's leads and plucks, lab.js SOUND_CHECK_PRESET).
pub const SPECIES: [u32; 75] = [
    0xa898680, 0x3dca8a81, 0x14687982, 0x46565683, 0x2acbca84, 0x5cb98a85, 0x5356786, 0x3bca8987,
    0x1acdb988, 0x46787689, 0x2b97568a, 0x5dfeca8b, 0xdca9a80, 0x39bdba81, 0x17879782, 0x49a87683,
    0x29878684, 0x53579785, 0xcb98a86, 0x3dca9a87, 0x1fdeca88, 0x4898a989, 0x2356798a, 0x5cba978b,
    0x79a8980, 0x79a8a81, 0x38acb982, 0x15767683, 0x44535784, 0x28679a85, 0x56465686, 0x89a8a87,
    0x34354688, 0x1dca8689, 0x44689a8a, 0x2978a98b, 0x56754680, 0x9baca81, 0x3ecaba83, 0x19ba8a82,
    0x49878684, 0x2bcab985, 0x5caca986, 0x9897687, 0x38979a88, 0x18a9b989, 0x4976868a, 0x29a9868b,
    0x59a98680, 0xcedb981, 0x78a8782, 0x3ecb9a83, 0x1b987984, 0x44346785, 0x2bacb986, 0x58aca987,
    0xdcaca88, 0x37575789, 0x18a8798a, 0x4dca8a8b, 0x26578780, 0x55464681, 0x79aca82, 0x3b9a8a83,
    0x168a8a84, 0x4aca9785, 0x2cb9ba86, 0x5cbca987, 0xca9a988, 0x36898780, 0x17568981, 0x49a86782,
    0x26424683, 0x5dca8984, 0x3575785,
];

/// Scales: major, minor, harmonic minor, Lydian, Phrygian.
pub const SCALES: [[u32; 7]; 5] = [
    [0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10], [0, 2, 3, 5, 7, 8, 11], [0, 2, 4, 6, 7, 9, 11],
    [0, 1, 3, 5, 7, 8, 10],
];

#[derive(Copy, Drop)]
pub struct Style {
    pub num: u32,
    pub den: u32,
    pub bpm_lo: u32,
    pub bpm_hi: u32,
    pub modes: Span<u32>,
    pub chord_bars: u32,
    /// melody rhythm cells and the phrase-end ones: eighths, 4 bits each from the low end
    pub cells: Span<u32>,
    pub end: Span<u32>,
    /// the figures a purchase picks from, events per bar: offset | duration << 11 | voice (bass:
    /// tone) << 22 | (velocity delta + 32) << 26
    pub accomps: Span<Span<u32>>,
    pub basses: Span<Span<u32>>,
    /// percussion figures: offset | drum note << 11 | (velocity delta + 64) << 18
    pub percs: Span<Span<u32>>,
    /// [lead, counter (unused), accomp, bass, pad] x [Magic, Hunter, Brute]
    pub palette: Span<u8>,
    /// progressions: four chord roots (scale degrees), 4 bits each from the low end
    pub progs: Span<u32>,
}

/// The styles: waltz, chorale, lullaby, dirge.
// On purpose (CASM size): one copy of the tables, not one per call site.
#[inline(never)]
pub fn style(s: u32) -> Box<Style> {
    BoxTrait::new(
        match s {
            0 => Style {
                num: 3,
                den: 4,
                bpm_lo: 140,
                bpm_hi: 170,
                modes: [0, 1, 2].span(),
                chord_bars: 1,
                cells: [36, 546, 6, 531, 8466, 8721, 66, 135441].span(),
                end: [6, 36].span(),
                accomps: [
                    [1783169504, 1380516800].span(), [1783169504, 1246119088].span(),
                    [1611063776, 1346822864, 1485235136, 1212605616].span(), [1247551968].span(),
                ]
                    .span(),
                basses: [[2148368384].span(), [2148368384, 1351451584].span(), [1747697664].span()]
                    .span(),
                percs: [[14229504, 11620832, 10572736].span(), [14229504, 11621312].span()].span(),
                palette: [0, 70, 64, 15, 44, 13, 17, 18, 99, 20, 27, 24, 33, 75, 32].span(),
                progs: [17232, 1072, 13632, 16437, 1040, 17696, 20547, 16720].span(),
            },
            1 => Style {
                num: 4,
                den: 4,
                bpm_lo: 66,
                bpm_hi: 84,
                modes: [0, 2].span(),
                chord_bars: 1,
                cells: [68, 1058, 548, 38, 8738].span(),
                end: [8, 68].span(),
                accomps: [
                    [2187137024, 1918702528].span(), [2054864896].span(),
                    [2051936256, 1649283552, 1917719488, 1649284512].span(),
                    [2014187520, 1615729120, 1888359360, 1615730080].span(),
                ]
                    .span(),
                basses: [
                    [1612517376, 1612518336].span(), [1614462976].span(),
                    [1612517376, 1482494912].span(),
                ]
                    .span(),
                percs: [[10569728, 9522112].span(), [10577920].span()].span(),
                palette: [95, 43, 47, 95, 43, 47, 95, 43, 47, 95, 43, 47, 33, 31, 29].span(),
                progs: [1072, 17232, 1040, 16643, 13632, 1045, 16688, 17184].span(),
            },
            2 => Style {
                num: 6,
                den: 8,
                bpm_lo: 84,
                bpm_hi: 100,
                modes: [0, 3, 1].span(),
                chord_bars: 1,
                cells: [51, 786, 291, 12561, 6, 801, 4371, 546].span(),
                end: [6, 51].span(),
                accomps: [
                    [2147934208, 1212604656, 1216799200, 2160517840, 1216799680, 1212605616].span(),
                    [2147934208, 1216798960, 1212604896, 2160517840, 1212605376, 1216799920].span(),
                    [1515577344, 1112924880].span(),
                    [2147934208, 1212604656, 1216799200, 1879499472, 1212605376, 1216799920].span(),
                ]
                    .span(),
                basses: [
                    [1477808128, 945132240].span(), [1345044480].span(),
                    [1477808128, 949326544].span(),
                ]
                    .span(),
                percs: [[8998912, 8999632].span(), [8998912, 7426528, 8999632, 7427248].span()]
                    .span(),
                palette: [45, 78, 17, 33, 0, 70, 17, 44, 99, 20, 27, 20, 33, 75, 32].span(),
                progs: [16432, 17232, 13632, 67, 1040, 17712, 1077, 17184].span(),
            },
            _ => Style {
                num: 4,
                den: 4,
                bpm_lo: 120,
                bpm_hi: 144,
                modes: [4, 2].span(),
                chord_bars: 2,
                cells: [8, 68, 38, 98, 548].span(),
                end: [8, 38].span(),
                accomps: [
                    [1521876992].span(), [1520181248, 1113334720].span(), [1249558528].span(),
                    [1624014848, 1208779232, 1489798080, 1074562464].span(),
                ]
                    .span(),
                basses: [[825933824].span(), [1077592064].span(), [1075585024, 811344832].span()]
                    .span(),
                percs: [[14239744].span(), [13719552, 12143552].span()].span(),
                palette: [64, 72, 62, 8, 9, 6, 44, 71, 19, 86, 85, 88, 29, 30, 28].span(),
                progs: [16, 4144, 848, 1584, 1376, 784, 101, 320].span(),
            },
        },
    )
}
