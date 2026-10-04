//! Self-contained Beast MIDI for a generic player (onchain-tinysynth plays a file exactly as
//! written: every play resets each channel to program 0 and adds nothing).
//!
//! On top of the score: a program change and a pan (CC10) on every voice at tick 0, and a drum
//! track on channel 10. Programs come from role pools (the TinyChip orchestration's) and are
//! TinyChip bank numbers, so sound settings that install those presets in the same slots are
//! selected by the file. Byte-identical to `beastFullMidi` in offchain/beast-sound/src/full_midi.js.
//!
//! Instruments: the highest voice leads (brighter leads above 120 BPM), the lowest is a bass (or
//! keys above E3), the voices between are pads when they rest a lot and keys when they move; no
//! preset twice. Drums: kick, half-time snare and eighth-note hats phrased in bar pairs, and a fill
//! into every section by tier (A tier 5, B tier 4, C tier 3, D tiers 1-2 with a cymbal on each
//! section's downbeat). Drum hits are note-ons only (one-shots), written with running status.

use core::dict::{Felt252Dict, Felt252DictTrait};
use crate::composition::beast_score::BeastForm;

const TAG_MTHD: u32 = 0x4D546864;
const TAG_MTRK: u32 = 0x4D54726B;

fn push_u32_be(ref out: Array<u8>, v: u32) {
    out.append(((v / 0x1000000) % 256).try_into().unwrap());
    out.append(((v / 0x10000) % 256).try_into().unwrap());
    out.append(((v / 0x100) % 256).try_into().unwrap());
    out.append((v % 256).try_into().unwrap());
}

fn push_vlq(ref out: Array<u8>, v: u32) {
    if v >= 0x200000 {
        out.append((0x80 + (v / 0x200000) % 128).try_into().unwrap());
    }
    if v >= 0x4000 {
        out.append((0x80 + (v / 0x4000) % 128).try_into().unwrap());
    }
    if v >= 0x80 {
        out.append((0x80 + (v / 0x80) % 128).try_into().unwrap());
    }
    out.append((v % 128).try_into().unwrap());
}

fn push_chunk(ref out: Array<u8>, tag: u32, body: Span<u8>) {
    push_u32_be(ref out, tag);
    push_u32_be(ref out, body.len());
    let mut i: u32 = 0;
    while i < body.len() {
        out.append(*body.at(i));
        i += 1;
    }
}

// role pools (TinyChip bank program numbers)
fn pool(role: u8) -> Span<u8> {
    if role == 0 {
        array![0, 2, 3, 1].span() // lead
    } else if role == 1 {
        array![50, 51, 53, 4].span() // bright lead
    } else if role == 2 {
        array![20, 61, 23, 21].span() // bass
    } else if role == 3 {
        array![12, 15, 18, 38].span() // keys
    } else {
        array![28, 33, 54, 34].span() // pad
    }
}

fn contains(list: @Array<u8>, x: u8) -> bool {
    let mut i: u32 = 0;
    let mut found = false;
    while i < list.len() {
        if *list.at(i) == x {
            found = true;
            break;
        }
        i += 1;
    }
    found
}

fn pick(role: u8, k: u32, ref used: Array<u8>) -> u8 {
    let p = pool(role);
    let mut i: u32 = 0;
    let mut chosen: u8 = *p.at(k % 4);
    let mut found = false;
    while i < 4 {
        let id = *p.at((k + i) % 4);
        if !contains(@used, id) {
            chosen = id;
            found = true;
            break;
        }
        i += 1;
    }
    if found {
        used.append(chosen);
    }
    chosen
}

/// (programs, pans) indexed by voice id 0..=max voice (absent voices get 0, 64).
pub fn voice_setup(form: @BeastForm, tempo_us: u32) -> (Array<u8>, Array<u8>) {
    let events = form.events.span();
    let mut max_voice: u32 = 0;
    let mut i: u32 = 0;
    while i < events.len() {
        let v = *events.at(i).voice_id;
        if v > max_voice {
            max_voice = v;
        }
        i += 1;
    }
    // per-voice sum of pitches, count, first and last onset
    let mut sums: Array<u64> = array![];
    let mut counts: Array<u64> = array![];
    let mut firsts: Array<u32> = array![];
    let mut lasts: Array<u32> = array![];
    let mut ids: Array<u32> = array![];
    let mut v: u32 = 0;
    while v <= max_voice {
        let mut sum: u64 = 0;
        let mut n: u64 = 0;
        let mut first: u32 = 0;
        let mut last: u32 = 0;
        let mut j: u32 = 0;
        while j < events.len() {
            let e = *events.at(j);
            if e.voice_id == v {
                if n == 0 || e.time < first {
                    first = e.time;
                }
                if n == 0 || e.time > last {
                    last = e.time;
                }
                sum += e.pitch.into();
                n += 1;
            }
            j += 1;
        }
        sums.append(sum);
        counts.append(n);
        firsts.append(first);
        lasts.append(last);
        if n > 0 {
            ids.append(v);
        }
        v += 1;
    }
    // order the present voices by mean pitch, lowest first (cross-multiplied); ties by voice id
    let mut order: Array<u32> = array![];
    let mut placed: u32 = 0;
    while placed < ids.len() {
        // pick the lowest remaining (selection, at most 6 voices)
        let mut best: u32 = 0;
        let mut best_set = false;
        let mut a: u32 = 0;
        while a < ids.len() {
            let id = *ids.at(a);
            let mut taken = false;
            let mut b: u32 = 0;
            while b < order.len() {
                if *order.at(b) == id {
                    taken = true;
                    break;
                }
                b += 1;
            }
            if !taken {
                if !best_set {
                    best = id;
                    best_set = true;
                } else {
                    let lhs = *sums.at(id) * *counts.at(best);
                    let rhs = *sums.at(best) * *counts.at(id);
                    if lhs < rhs || (lhs == rhs && id < best) {
                        best = id;
                    }
                }
            }
            a += 1;
        }
        order.append(best);
        placed += 1;
    }
    let hash_u256: u256 = (*form.score_hash).into();
    let hash: u32 = (hash_u256.low % 0x100000000).try_into().unwrap();
    let h4 = hash / 16;
    let h8 = hash / 256;
    let mut progs: Felt252Dict<u8> = Default::default();
    let mut used: Array<u8> = array![];
    let nvo = order.len();
    let mut i: u32 = 0;
    while i < nvo {
        let id = *order.at(i);
        let program = if i == nvo - 1 {
            pick(if tempo_us < 500000 { 1 } else { 0 }, hash % 4, ref used)
        } else if i == 0 {
            pick(if *sums.at(id) < 52 * *counts.at(id) { 2 } else { 3 }, h4 % 4, ref used)
        } else {
            let span: u64 = (*lasts.at(id) - *firsts.at(id) + 480).into();
            pick(if 4800 * *counts.at(id) < 7 * span { 4 } else { 3 }, (h8 + i) % 4, ref used)
        };
        progs.insert(id.into(), program);
        i += 1;
    }
    // pan across the present voices in voice order: floor((960 (n-1) + 10880 i) / (100 (n-1)))
    let mut pans: Felt252Dict<u8> = Default::default();
    let nv = ids.len();
    let mut i: u32 = 0;
    while i < nv {
        let pan: u32 = if nv < 2 {
            64
        } else {
            (960 * (nv - 1) + 10880 * i) / (100 * (nv - 1))
        };
        pans.insert((*ids.at(i)).into(), pan.try_into().unwrap());
        i += 1;
    }
    let mut out_p: Array<u8> = array![];
    let mut out_pan: Array<u8> = array![];
    let mut v: u32 = 0;
    while v <= max_voice {
        out_p.append(progs.get(v.into()));
        let pv = pans.get(v.into());
        out_pan.append(if pv == 0 && *counts.at(v) == 0 { 64 } else { pv });
        v += 1;
    }
    (out_p, out_pan)
}

/// The fill for a tier: 0 A (tier 5), 1 B (tier 4), 2 C (tier 3), 3 D (tiers 1-2).
fn fill_for(tier: u8) -> u8 {
    if tier >= 5 {
        0
    } else if tier == 4 {
        1
    } else if tier == 3 {
        2
    } else {
        3
    }
}

// fill notes (offset, key, velocity) and length in beats
fn fill_notes(f: u8) -> Span<(u32, u8, u8)> {
    if f == 0 {
        array![(0, 38, 88), (240, 38, 106)].span()
    } else if f == 1 {
        array![(0, 38, 72), (120, 38, 84), (240, 38, 96), (360, 38, 108)].span()
    } else if f == 2 {
        array![
            (0, 36, 100), (0, 38, 80), (240, 38, 88), (480, 38, 92), (600, 38, 100), (720, 38, 108),
            (840, 38, 116),
        ]
            .span()
    } else {
        array![
            (0, 50, 84), (120, 50, 88), (240, 48, 92), (360, 48, 96), (480, 47, 100), (600, 45, 104),
            (720, 43, 108), (840, 41, 112), (840, 36, 110),
        ]
            .span()
    }
}

/// The drum track body (channel 10, running status) for a form of `length` ticks in sections of
/// `sec`, ending with End-of-Track at `length`. Empty when there is nothing to play.
pub fn drum_track(length: u32, sec: u32, tier: u8) -> Array<u8> {
    let f = fill_for(tier);
    let notes = fill_notes(f);
    let region: u32 = if f >= 2 { 960 } else { 480 };
    let fill_kick0 = f == 2; // only fill C has a kick at its start
    let mut data: Array<u8> = array![];
    let mut t: u32 = 0;
    let mut first = true;
    let mut u: u32 = 0;
    while u < length {
        let rel = u % sec;
        let fill_start = sec - region;
        let in_fill = rel >= fill_start;
        let mut hits: Array<(u8, u8)> = array![];
        if f == 3 && rel == 0 {
            hits.append((49, 76));
        }
        if in_fill {
            let mut i: u32 = 0;
            while i < notes.len() {
                let (o, k, vel) = *notes.at(i);
                if o == rel - fill_start {
                    hits.append((k, vel));
                }
                i += 1;
            }
        }
        if u % 240 == 0 {
            let bar = rel / 1920;
            let second = bar % 2 == 1;
            let q = rel % 1920;
            if q == 0 {
                hits.append((36, if second { 104 } else { 122 }));
            }
            if !in_fill && second && q == 1200 {
                hits.append((36, 86));
            }
            if in_fill && q == 960 && !(fill_kick0 && rel == fill_start) {
                hits.append((36, 100));
            }
            if !in_fill && q == 960 {
                hits.append((38, if second { 88 } else { 94 }));
            }
            let open = !in_fill && second && q == 1680;
            let mut hv: u8 = if q == 0 {
                80
            } else if u % 480 == 0 {
                70
            } else {
                52
            };
            if in_fill {
                hv -= 12;
            }
            if open {
                hits.append((46, 64));
            } else {
                hits.append((42, hv));
            }
        }
        let mut i: u32 = 0;
        while i < hits.len() {
            let (k, vel) = *hits.at(i);
            push_vlq(ref data, u - t);
            if first {
                data.append(0x99);
                first = false;
            }
            data.append(k);
            data.append(vel);
            t = u;
            i += 1;
        }
        u += 120;
    }
    if first {
        return array![];
    }
    push_vlq(ref data, if length > t { length - t } else { 0 });
    data.append(0xFF);
    data.append(0x2F);
    data.append(0);
    data
}

/// The whole self-contained file: tempo track (End-of-Track at the form length), one track per
/// voice (program and pan at tick 0, then the notes), and the drum track.
pub fn beast_form_to_full_smf_bytes(form: @BeastForm, tempo_us: u32, tier: u8) -> Array<u8> {
    let events = form.events.span();
    let (programs, pans) = voice_setup(form, tempo_us);
    let max_voice: u32 = programs.len() - 1;
    let length = *form.length_ticks;
    let sections: u32 = (*form.section_count).into();
    let sec = length / sections;

    let mut tracks: Array<Array<u8>> = array![];
    let mut tempo_track: Array<u8> = array![0, 0xFF, 0x51, 0x03];
    tempo_track.append(((tempo_us / 0x10000) % 256).try_into().unwrap());
    tempo_track.append(((tempo_us / 0x100) % 256).try_into().unwrap());
    tempo_track.append((tempo_us % 256).try_into().unwrap());
    push_vlq(ref tempo_track, length);
    tempo_track.append(0xFF);
    tempo_track.append(0x2F);
    tempo_track.append(0);
    tracks.append(tempo_track);

    let mut v: u32 = 0;
    while v <= max_voice {
        let ch: u8 = (v % 16).try_into().unwrap();
        let mut track: Array<u8> = array![0, 0xC0 + ch, *programs.at(v), 0, 0xB0 + ch, 10, *pans.at(v)];
        let mut t: u32 = 0;
        let mut any = false;
        let mut j: u32 = 0;
        while j < events.len() {
            let e = *events.at(j);
            if e.voice_id == v {
                any = true;
                push_vlq(ref track, e.time - t);
                track.append(0x90 + ch);
                track.append(e.pitch);
                track.append(e.velocity);
                let off = e.time + e.duration;
                push_vlq(ref track, off - e.time);
                track.append(0x80 + ch);
                track.append(e.pitch);
                track.append(64);
                t = off;
            }
            j += 1;
        }
        if any {
            track.append(0);
            track.append(0xFF);
            track.append(0x2F);
            track.append(0);
            tracks.append(track);
        }
        v += 1;
    }
    let drums = drum_track(length, sec, tier);
    if drums.len() > 0 {
        tracks.append(drums);
    }

    let mut out: Array<u8> = array![];
    let n: u32 = tracks.len();
    let header: Array<u8> = array![
        0, 1, ((n / 256) % 256).try_into().unwrap(), (n % 256).try_into().unwrap(), 0x01, 0xE0,
    ];
    push_chunk(ref out, TAG_MTHD, header.span());
    let mut k: u32 = 0;
    while k < tracks.len() {
        push_chunk(ref out, TAG_MTRK, tracks.at(k).span());
        k += 1;
    }
    out
}
