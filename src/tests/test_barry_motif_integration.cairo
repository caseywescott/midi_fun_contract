use koji::composition::barry_harris::ChordFamily;
use koji::composition::barry_labyrinth::{
    generate_barry_labyrinth_phrase, motif_from_barry_labyrinth_phrase, BarryTextureMode,
};
use koji::composition::barry_profiles::BarryRuleProfile;

#[test]
fn test_motif_from_labyrinth_phrase() {
    let seed: felt252 = 0xB200_0000_0000_00F1;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 8, BarryRuleProfile::BebopLine, 48, 72,
    );
    let motifs = motif_from_barry_labyrinth_phrase(phrase, seed, 48, 72);
    assert(motifs.len() > 0, 'motif notes');
}

#[test]
fn test_motif_deterministic() {
    let seed: felt252 = 0xB200_0000_0000_00F1;
    let phrase_a = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 6, BarryRuleProfile::BebopLine, 48, 72,
    );
    let phrase_b = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 6, BarryRuleProfile::BebopLine, 48, 72,
    );
    let a = motif_from_barry_labyrinth_phrase(phrase_a, seed, 48, 72);
    let b = motif_from_barry_labyrinth_phrase(phrase_b, seed, 48, 72);
    assert(a.len() == b.len(), 'same len');
}

#[test]
fn test_monophonic_line_cells_populated() {
    let seed: felt252 = 0xB200_0000_0100_0001;
    let phrase = generate_barry_labyrinth_phrase(
        seed, 0, ChordFamily::Major6Dim, 8, BarryRuleProfile::BebopLine, 48, 72,
    );
    if phrase.plan.texture_mode == BarryTextureMode::MonophonicLine {
        assert(phrase.line_cells.len() > 0, 'line cells');
    }
}
