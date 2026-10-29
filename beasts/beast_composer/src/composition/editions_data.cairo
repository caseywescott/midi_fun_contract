//! Tables of the Monthly Track Editions engine (editions.cairo), generated from
//! offchain/beast-sound/src/editions_lite.js by offchain/beast-sound/onchain/editions_cairo.mjs. Do
//! not edit: change the source and rerun the generator.

/// Species 1..75: tonic pitch class (bits 0-3), then the first 6 Genesis theme degrees + 8
/// (4 bits each, from bit 4).
pub const SPECIES: [u32; 75] = [
    0xa898680, 0xdca8a81, 0x4687982, 0x6565683, 0xacbca84, 0xcb98a85, 0x5356786, 0xbca8987,
    0xacdb988, 0x6787689, 0xb97568a, 0xdfeca8b, 0xdca9a80, 0x9bdba81, 0x7879782, 0x9a87683,
    0x9878684, 0x3579785, 0xcb98a86, 0xdca9a87, 0xfdeca88, 0x898a989, 0x356798a, 0xcba978b,
    0x79a8980, 0x79a8a81, 0x8acb982, 0x5767683, 0x4535784, 0x8679a85, 0x6465686, 0x89a8a87,
    0x4354688, 0xdca8689, 0x4689a8a, 0x978a98b, 0x6754680, 0x9baca81, 0xecaba83, 0x9ba8a82,
    0x9878684, 0xbcab985, 0xcaca986, 0x9897687, 0x8979a88, 0x8a9b989, 0x976868a, 0x9a9868b,
    0x9a98680, 0xcedb981, 0x78a8782, 0xecb9a83, 0xb987984, 0x4346785, 0xbacb986, 0x8aca987,
    0xdcaca88, 0x7575789, 0x8a8798a, 0xdca8a8b, 0x6578780, 0x5464681, 0x79aca82, 0xb9a8a83,
    0x68a8a84, 0xaca9785, 0xcb9ba86, 0xcbca987, 0xca9a988, 0x6898780, 0x7568981, 0x9a86782,
    0x6424683, 0xdca8984, 0x3575785,
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
    /// events per bar: offset | duration << 11 | voice << 22 | (velocity delta + 32) << 26
    pub accomp: Span<u32>,
    pub bass: Span<u32>,
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
                cells: [36, 546, 6, 531, 8466].span(),
                end: [6, 36].span(),
                accomp: [1783169504, 1380516800].span(),
                bass: [2148368384].span(),
                palette: [0, 70, 64, 15, 44, 13, 17, 18, 99, 20, 27, 24, 33, 75, 32].span(),
                progs: [17232, 1072, 13632, 16437].span(),
            },
            1 => Style {
                num: 4,
                den: 4,
                bpm_lo: 66,
                bpm_hi: 84,
                modes: [0, 2].span(),
                chord_bars: 1,
                cells: [68].span(),
                end: [8].span(),
                accomp: [2187137024, 1918702528].span(),
                bass: [1612517376, 1612518336].span(),
                palette: [95, 43, 47, 95, 43, 47, 95, 43, 47, 95, 43, 47, 33, 31, 29].span(),
                progs: [1072, 17232, 1040, 16643].span(),
            },
            2 => Style {
                num: 6,
                den: 8,
                bpm_lo: 84,
                bpm_hi: 100,
                modes: [0, 3, 1].span(),
                chord_bars: 1,
                cells: [51, 786, 291, 12561, 6].span(),
                end: [6, 51].span(),
                accomp: [2147934208, 1212604656, 1216799200, 2160517840, 1216799680, 1212605616]
                    .span(),
                bass: [1477808128, 945132240].span(),
                palette: [45, 78, 17, 33, 0, 70, 17, 44, 99, 20, 27, 20, 33, 75, 32].span(),
                progs: [16432, 17232, 13632, 67].span(),
            },
            _ => Style {
                num: 4,
                den: 4,
                bpm_lo: 120,
                bpm_hi: 144,
                modes: [4, 2].span(),
                chord_bars: 2,
                cells: [8, 68, 38].span(),
                end: [8].span(),
                accomp: [1521876992].span(),
                bass: [825933824].span(),
                palette: [64, 72, 62, 8, 9, 6, 44, 71, 19, 86, 85, 88, 29, 30, 28].span(),
                progs: [16, 4144, 848, 1584].span(),
            },
        },
    )
}
