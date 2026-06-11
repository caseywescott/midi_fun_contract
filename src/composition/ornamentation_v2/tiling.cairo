//! Rhythmic tiling validation (§10).

use core::array::ArrayTrait;
use koji::composition::ornamentation_v2::pitch::set_bool_at;
use koji::composition::ornamentation_v2::types::{MusicalTile, TilingContext, V2NoteEvent};
use koji::composition::ornamentation_v2::validation::{
    preserves_coverage, preserves_no_collision,
};

pub fn cell_len(tile: MusicalTile, motif_onsets: Span<u32>, durations: Span<u32>) -> u32 {
    if durations.len() == 0 {
        return tile.period;
    }
    let mut total: u32 = 0;
    let mut i: u32 = 0;
    loop {
        if i >= durations.len() {
            break;
        }
        total += *durations.at(i);
        i += 1;
    };
    total
}

pub fn collect_onsets(events: Span<V2NoteEvent>) -> Array<u32> {
    let mut out: Array<u32> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= events.len() {
            break;
        }
        out.append((*events.at(i)).start);
        i += 1;
    };
    out
}

pub fn validate_tiling_texture(
    tile: MusicalTile,
    ctx: TilingContext,
    voice_events: Span<V2NoteEvent>,
    target_onsets: Span<u32>,
    other_onsets: Span<u32>,
    motif_durations: Span<u32>,
) -> bool {
    let len = cell_len(tile, array![].span(), motif_durations);
    if !preserves_coverage(tile.start, len, target_onsets, voice_events) {
        return false;
    }
    preserves_no_collision(voice_events, other_onsets, tile.voice_index, ctx.collision_policy)
}

pub fn structural_voices_tile(
    voice_onsets: Span<Span<u32>>, period: u32, collision_policy: u8,
) -> bool {
    let mut covered: Array<bool> = ArrayTrait::new();
    let mut i: u32 = 0;
    loop {
        if i >= period {
            break;
        }
        covered.append(false);
        i += 1;
    };
    let mut vi: u32 = 0;
    loop {
        if vi >= voice_onsets.len() {
            break;
        }
        let onsets = *voice_onsets.at(vi);
        let mut j: u32 = 0;
        loop {
            if j >= onsets.len() {
                break;
            }
            let t = *onsets.at(j) % period;
            if collision_policy == 0 {
                if *covered.at(t) {
                    return false;
                }
            }
            covered = set_bool_at(covered, t, true);
            j += 1;
        };
        vi += 1;
    };
    true
}
