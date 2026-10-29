//! A token's `sound_effects` (0-3; the Sound Manager plays 4-31 as 0) as a performance of a written
//! song or Sound Check: the mega sound, a faster tempo, louder notes and an articulation. The
//! stored inputs never change; 0 plays them as written. The values are the Beasts reference
//! manager's (loothero/midi_fun_contract eebed3a, `recipe.cairo`), so a manager tested against it
//! hears the same performances.
//!
//! | code | mega | tempo           | velocity ceiling | articulation |
//! |------|------|-----------------|------------------|--------------|
//! | 0    | no   | as written      | as written       | as written   |
//! | 1    | yes  | 25000 us faster | +12              | tenuto (2)   |
//! | 2    | no   | 30000 us faster | +8               | portato (5)  |
//! | 3    | yes  | 45000 us faster | +15              | accent (3)   |

use crate::inputs::{ComposerInputs, ScoreInputs, validate_inputs, validate_performance};

pub fn is_mega(sound_effects: u8) -> bool {
    validate_performance(sound_effects);
    sound_effects == 1 || sound_effects == 3
}

pub fn apply_performance(x: ComposerInputs, sound_effects: u8) -> ComposerInputs {
    validate_inputs(x);
    validate_performance(sound_effects);
    match x {
        ComposerInputs::Song(mut song) => {
            let p = song.score;
            let (tempo_us, velocity_ceiling, articulation_profile) = performed(
                p.tempo_us, p.velocity_ceiling, p.articulation_profile, sound_effects,
            );
            song.score = ScoreInputs { tempo_us, velocity_ceiling, articulation_profile, ..p };
            ComposerInputs::Song(song)
        },
        ComposerInputs::SoundCheck(mut check) => {
            let (tempo_us, velocity_ceiling, articulation_profile) = performed(
                check.tempo_us, check.velocity_ceiling, check.articulation_profile, sound_effects,
            );
            check.tempo_us = tempo_us;
            check.velocity_ceiling = velocity_ceiling;
            check.articulation_profile = articulation_profile;
            ComposerInputs::SoundCheck(check)
        },
    }
}

/// The performed tempo, velocity ceiling and articulation. 0 keeps them: the written tempo is at
/// least 1 and the ceiling at most 127 (`validate_inputs`), so no change and no lift leave them as
/// written. One copy for songs and Sound Checks (CASM size).
#[inline(never)]
fn performed(tempo_us: u32, ceiling: u8, articulation: u8, sound_effects: u8) -> (u32, u8, u8) {
    let (faster, lift, articulation): (u32, u8, u8) = match sound_effects {
        0 => (0, 0, articulation),
        1 => (25000, 12, 2),
        2 => (30000, 8, 5),
        _ => (45000, 15, 3),
    };
    (faster_tempo(tempo_us, faster), lifted(ceiling, lift), articulation)
}

fn faster_tempo(tempo_us: u32, faster: u32) -> u32 {
    if tempo_us > faster {
        tempo_us - faster
    } else {
        1
    }
}

fn lifted(ceiling: u8, lift: u8) -> u8 {
    let n: u32 = ceiling.into() + lift.into();
    if n > 127 {
        127
    } else {
        n.try_into().unwrap()
    }
}
