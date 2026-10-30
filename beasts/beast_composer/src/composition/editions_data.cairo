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

/// How many styles the calendar takes in turn.
pub const STYLE_COUNT: u32 = 9;

/// The styles: waltz, chorale, lullaby, dirge, boss, shanty, march, dungeon, tango.
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
            3 => Style {
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
            4 => Style {
                num: 4,
                den: 4,
                bpm_lo: 150,
                bpm_hi: 176,
                modes: [1, 2, 4].span(),
                chord_bars: 1,
                cells: [8738, 139793, 16658, 8723, 2232593, 548, 1058].span(),
                end: [8, 68, 38].span(),
                accomps: [
                    [1921360112, 1652925136, 1921361072, 1652926096].span(),
                    [1783398400, 1783399360].span(),
                    [2055618560, 1518748128, 1787183824, 1518749088].span(),
                    [
                        1745281024, 1346822384, 1351016928, 1346822864, 1745281984, 1346823344,
                        1351017888, 1346823824,
                    ]
                        .span(),
                ]
                    .span(),
                basses: [
                    [
                        2147893248, 1342587120, 1879458272, 1342587600, 2147894208, 1342588080,
                        1879459232, 1342588560,
                    ]
                        .span(),
                    [
                        2147893248, 1489387760, 1879458272, 1489388240, 2147894208, 1489388720,
                        1879459232, 1489389200,
                    ]
                        .span(),
                    [2148384768, 1619902944, 2014168000, 1619903904].span(),
                ]
                    .span(),
                percs: [
                    [15278080, 8999152, 14234080, 8999632, 15279040, 9000112, 14235040, 9000592]
                        .span(),
                    [15278080, 13181648, 14234560, 9524880].span(),
                ]
                    .span(),
                palette: [64, 72, 62, 64, 72, 62, 99, 19, 18, 85, 88, 88, 31, 28, 30].span(),
                progs: [1616, 1072, 17760, 17232, 101, 16400, 17968, 17248].span(),
            },
            5 => Style {
                num: 6,
                den: 8,
                bpm_lo: 132,
                bpm_hi: 156,
                modes: [0, 1, 2].span(),
                chord_bars: 1,
                cells: [51, 786, 12561, 4371, 4626, 801].span(),
                end: [6, 51].span(),
                accomps: [
                    [1648771312, 1246118368, 1648772032, 1246119088].span(),
                    [1515536384, 1381319376].span(), [1787183344, 1787184064].span(),
                    [1745281024, 1351016688, 1346822624, 1757864656, 1351017408, 1346823344].span(),
                ]
                    .span(),
                basses: [
                    [2148712448, 1616036560].span(), [2148712448, 1620230864].span(),
                    [1747697664].span(),
                ]
                    .span(),
                percs: [
                    [14753792, 10572256, 14754512, 10572976].span(), [14239744, 13720272].span(),
                ]
                    .span(),
                palette: [70, 64, 62, 70, 64, 62, 95, 43, 95, 24, 27, 71, 32, 29, 30].span(),
                progs: [1072, 16448, 17232, 16432, 1077, 1040, 1344, 67].span(),
            },
            6 => Style {
                num: 2,
                den: 4,
                bpm_lo: 104,
                bpm_hi: 124,
                modes: [0, 3].span(),
                chord_bars: 2,
                cells: [34, 529, 19, 274, 4369, 4].span(),
                end: [4, 34].span(),
                accomps: [
                    [1648771552].span(), [1514512624, 1514513104].span(),
                    [1514962944, 1246527968].span(), [1648566752, 1380131536].span(),
                ]
                    .span(),
                basses: [
                    [2148302848].span(), [2148302848, 1749844448].span(),
                    [2147893248, 1623605728].span(),
                ]
                    .span(),
                percs: [
                    [15278080, 14234080, 11088592].span(), [15278080, 10563824, 14234080].span(),
                ]
                    .span(),
                palette: [47, 47, 62, 47, 47, 62, 18, 44, 99, 20, 24, 88, 29, 31, 28].span(),
                progs: [16448, 1072, 1024, 16432, 16720, 1027, 17728, 1040].span(),
            },
            7 => Style {
                num: 4,
                den: 4,
                bpm_lo: 76,
                bpm_hi: 96,
                modes: [1, 4, 2].span(),
                chord_bars: 2,
                cells: [8, 68, 38, 98, 563, 548].span(),
                end: [8, 38].span(),
                accomps: [
                    [
                        1476804608, 1078345968, 1082540512, 1078346448, 1476805568, 1078346928,
                        1082541472, 1078347408,
                    ]
                        .span(),
                    [1385963520, 1117529024].span(), [1477214208, 1221362624].span(),
                    [981123072].span(),
                ]
                    .span(),
                basses: [[1211809792].span(), [1344020480, 1079780288].span(), [960151552].span()]
                    .span(),
                percs: [[12666880, 10575264].span(), [12132352, 11094976].span()].span(),
                palette: [45, 78, 72, 45, 78, 72, 44, 19, 71, 86, 85, 88, 75, 31, 30].span(),
                progs: [20560, 16, 1376, 16432, 1616, 784, 17712, 25856].span(),
            },
            _ => Style {
                num: 4,
                den: 4,
                bpm_lo: 110,
                bpm_hi: 128,
                modes: [1, 2].span(),
                chord_bars: 1,
                cells: [8723, 8738, 1043, 16913, 548, 139538].span(),
                end: [8, 68].span(),
                accomps: [
                    [1782886400, 1380233696, 1782887360, 1380234656].span(),
                    [1514451184, 1514451664, 1514452144, 1514452624].span(),
                    [1917104128, 1648669392, 1648670112].span(), [1653170176, 1514759104].span(),
                ]
                    .span(),
                basses: [
                    [
                        2148179968, 1484988776, 1757864416, 1619452624, 2148180928, 1484989736,
                        1757865376, 1619453584,
                    ]
                        .span(),
                    [2148917248, 1615258320, 2148918208, 1615259280].span(),
                    [2148384768, 1624097248, 2014168000, 1619903904].span(),
                ]
                    .span(),
                percs: [
                    [14229504, 12667600, 13185984, 10048928].span(),
                    [14229504, 9523560, 12661216, 11613600].span(),
                ]
                    .span(),
                palette: [0, 70, 64, 0, 70, 64, 18, 17, 99, 27, 24, 20, 28, 32, 29].span(),
                progs: [1072, 1104, 16432, 17760, 67, 1040, 1077, 12352].span(),
            },
        },
    )
}
