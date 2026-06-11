# v2 Ornamentation Showcase

One MIDI demo per ornament kind, plus a full catalog. All examples use C Ionian (tonic C4) on channel 0.

## Generate MIDIs

```bash
./scripts/generate_ornamentation_v2_demo_midis.sh
```

Output: `demos/ornamentation_v2/*.mid` (36 files: catalog + 35 kinds)

## Code API

```cairo
use koji::composition::ornamentation_v2::showcase::{
    showcase_events_for_kind, showcase_catalog_events, showcase_kind_slug,
};
use koji::composition::ornamentation_v2::types::ORN_SUSPENSION_43;

// Single ornament (e.g. 4–3 suspension)
let events = showcase_events_for_kind(ORN_SUSPENSION_43);

// All kinds in one phrase with gaps
let catalog = showcase_catalog_events(8); // 8-tick gap between examples
```

Lower-level direct generation:

```cairo
use koji::composition::ornamentation_v2::ornaments::ornament_generate;
use koji::composition::ornamentation_v2::types::{
    OrnamentContext, ORN_NEIGHBOR_UPPER,
};

let ctx = OrnamentContext { /* ... */ };
let chord = array![0_u8, 4, 7];
let notes = ornament_generate(
    ORN_NEIGHBOR_UPPER,
    ctx,
    4,   // anchor degree (G)
    4,   // prev degree
    7,   // next degree (B)
    0,   // start tick
    12,  // duration (needs >= 3 for neighbor)
    60,  // tonic MIDI
    chord.span(),
    0,   // bass pc
    chord.span(),
    chord.span(),
    1,   // ornament id
);
```

## Catalog

| File | Kind | Contour |
|------|------|---------|
| `01_passing_asc` | Passing ascending | C–D–E fill |
| `02_passing_desc` | Passing descending | E–D–C fill |
| `03_neighbor_upper` | Upper neighbor | G–A–G |
| `04_neighbor_lower` | Lower neighbor | G–F–G |
| `05_double_neighbor_uf` | Double neighbor (upper first) | G–A–F–G |
| `06_double_neighbor_lf` | Double neighbor (lower first) | G–F–A–G |
| `07_anticipation` | Anticipation | early arrival on downbeat |
| `08_suspension_43` | Suspension 4–3 | held E, step down |
| `09_suspension_76` | Suspension 7–6 | held G, step down |
| `10_suspension_98` | Suspension 9–8 | held D, step down |
| `11_suspension_65` | Suspension 6–5 | held C over F# bass |
| `12_suspension_23_bass` | Bass suspension 2–3 | bass resolves up |
| `13_retardation` | Retardation | held G, step up |
| `14_appoggiatura_upper` | Upper appoggiatura | leap up, step down |
| `15_appoggiatura_lower` | Lower appoggiatura | leap down, step up |
| `16_escape_upper` | Escape tone | step up, leap away |
| `17_escape_lower` | Escape tone | step down, leap away |
| `18_echappee_upper` | Échappée | leap up, step in |
| `19_echappee_lower` | Échappée | leap down, step in |
| `20_cambiata` | Cambiata (5-note) | 0,−1,−3,−2,−1 degrees |
| `21_mordent_upper` | Upper mordent | G–A–G |
| `22_mordent_lower` | Lower mordent | G–F–G |
| `23_turn_upper` | Turn (upper first) | A–G–F–G |
| `24_turn_lower` | Turn (lower first) | F–G–A–G |
| `25_trill_upper` | Upper trill | G↔A alternation |
| `26_trill_lower` | Lower trill | G↔F alternation |
| `27_acciaccatura_upper` | Grace note above | quick A before G |
| `28_acciaccatura_lower` | Grace note below | quick F before G |
| `29_chromatic_approach_upper` | Chromatic from above | F#→G |
| `30_chromatic_approach_lower` | Chromatic from below | G#→G |
| `31_enclosure_uf` | Enclosure (upper first) | A–F–G |
| `32_enclosure_lf` | Enclosure (lower first) | F–A–G |
| `33_arpeggiation_up` | Arpeggiation up | C–E–G |
| `34_arpeggiation_down` | Arpeggiation down | G–E–C |
| `35_pedal_hold` | Pedal / common tone | sustained C |
| `00_catalog_all_kinds` | Full catalog | all of the above in sequence |

## Tests

Individual MIDI export tests live in `src/tests/test_ornamentation_v2_midi.cairo`.
Unit tests for contours and validation are in `src/tests/test_ornamentation_v2.cairo`.
