//! The authored Cyclops Sound Check: the entire original lab track 504.
//! Eight Arp/FX timbres, 175 BPM as written, ten beats each. Names and drift do not retune
//! the score. Token effects use the standard Check tempo, articulation and velocity rules;
//! Mega retains the eight Arp/FX programs rather than replacing their identity. One fixed nine-note
//! descriptor is reused for all eight programs through the existing paired-note MIDI writer.
//! The independent original-file fixture checks every byte.
use midi::smf::{TrackWriterTrait, smf_bytes};
use crate::composition::beast_v11::articulated_duration;
use crate::composition::full_midi::note_on_off;
use crate::inputs::SoundCheckInputs;
use crate::opaque::opaque;

pub const CYCLOPS_SPECIES: u8 = 64;
pub const CYCLOPS_CHECK_TEMPO_US: u32 = 342857;
pub const CYCLOPS_CHECK_LENGTH: u32 = 38400;
// Absolute offset, original gate and pitch: the original nine-note phrase.
const NOTES: [(u32, u32, u8); 9] = [
    (0, 440, 60), (480, 440, 64), (960, 440, 67), (1440, 440, 72), (1920, 1100, 67), (3360, 58, 60),
    (3600, 58, 64), (3840, 58, 67), (4080, 58, 72),
];

pub fn cyclops_sound_check_smf_bytes() -> Array<u8> {
    let x = crate::composition::sound_check::sound_check_inputs(
        crate::composition::beast_v3_sound::PackableBeastV3 {
            id: 64,
            prefix: 0,
            suffix: 0,
            level: 1,
            health: 100,
            shiny: 0,
            animated: 0,
            tier: 3,
            beast_type: 2,
        },
    );
    smf_bytes(1, 480, cyclops_sound_check_tracks(x).span())
}

/// The same authored score as track bodies for the shared packed-SMF composition path.
pub fn cyclops_sound_check_tracks(x: SoundCheckInputs) -> Array<Array<u8>> {
    tracks_for(x.tempo_us, x.articulation_profile, x.velocity_ceiling)
}

fn tracks_for(tempo_us: u32, profile: u8, ceiling: u8) -> Array<Array<u8>> {
    let mut tempo = TrackWriterTrait::new();
    tempo.tempo(0, tempo_us);
    let mut lead = TrackWriterTrait::new();
    lead.program(0, 0, 34);
    lead.control(0, 0, 7, 100);
    lead.control(0, 0, 10, 64);
    // Fixed private counter: starts at0 and visits each of the eight timbres once.
    let mut block: u8 = opaque(0);
    while block != 8 {
        let at: u32 = block.into() * 4800;
        if block != 0 {
            lead.program(at, 0, 34 + block);
        }
        for entry in NOTES.span() {
            let (offset, original_gate, key) = *entry;
            // Preserve the authored blips below Casey's sixty-tick articulation floor.
            let gate = if original_gate == 58 {
                58
            } else {
                articulated_duration(original_gate, profile)
            };
            let time = at + offset;
            let written_velocity = if profile == 3 && time % 1920 == 0 {
                108
            } else {
                100
            };
            let velocity = if written_velocity < ceiling {
                written_velocity
            } else {
                ceiling
            };
            note_on_off(ref lead, 0, time, gate, key, velocity);
        }
        block += 1;
    }
    array![tempo.finish_at(CYCLOPS_CHECK_LENGTH), lead.finish_at(CYCLOPS_CHECK_LENGTH)]
}
