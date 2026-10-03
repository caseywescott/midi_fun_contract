/// =========================================
/// ================ PATTERNS ===============
/// =========================================

#[derive(Copy, Drop, Serde)]
pub enum Modes {
    Major: (),
    Minor: (),
    Lydian: (),
    Mixolydian: (),
    Dorian: (),
    Phrygian: (),
    Locrian: (),
    Aeolian: (),
    HarmonicMinor: (),
    NaturalMinor: (),
    Chromatic: (),
    Pentatonic: (),
    MelodicMinor: (),
    DorianFlat2: (),
    LydianAugmented: (),
    LydianDominant: (),
    MixolydianFlat13: (),
    LocrianNatural2: (),
    Altered: (),
    HarmonicMajor: (),
    DorianFlat5: (),
    PhrygianFlat4: (),
    LydianFlat3: (),
    MixolydianFlat2: (),
    LydianAugmentedSharp2: (),
    LocrianDoubleFlat7: (),
    DorianSharp4: (),
    LocrianNatural6: (),
    WholeTone: (),
    HalfWholeDiminished: (),
    WholeHalfDiminished: (),
}
