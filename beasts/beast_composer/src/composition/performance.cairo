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
    if sound_effects == 0 {
        return x;
    }
    let (faster, lift, articulation): (u32, u8, u8) = match sound_effects {
        1 => (25000, 12, 2),
        2 => (30000, 8, 5),
        _ => (45000, 15, 3),
    };
    match x {
        ComposerInputs::Song(mut song) => {
            let p = song.score;
            song
                .score =
                    ScoreInputs {
                        tempo_us: faster_tempo(p.tempo_us, faster),
                        velocity_ceiling: lifted(p.velocity_ceiling, lift),
                        articulation_profile: articulation,
                        ..p,
                    };
            ComposerInputs::Song(song)
        },
        ComposerInputs::SoundCheck(mut check) => {
            check.tempo_us = faster_tempo(check.tempo_us, faster);
            check.velocity_ceiling = lifted(check.velocity_ceiling, lift);
            check.articulation_profile = articulation;
            ComposerInputs::SoundCheck(check)
        },
    }
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
