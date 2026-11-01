//! Standard MIDI File writing.
//!
//! ```cairo
//! let mut tempo = TrackWriterTrait::new();
//! tempo.tempo(0, 500000); // 120 BPM
//! let mut lead = TrackWriterTrait::new();
//! lead.program(0, 0, 80);
//! lead.note_on(0, 0, 60, 100);
//! lead.note_off(480, 0, 60, 64);
//! let file = smf_bytes(1, 480, array![tempo.finish_at(1920), lead.finish()].span());
//! ```
//!
//! Event times are absolute ticks and must not go backwards within a track (the writer stores
//! deltas). Channels are 0-based (9 is General MIDI percussion).

use core::num::traits::OverflowingSub;
use crate::pack::chunks_to_byte_array;

pub const MTHD: u32 = 0x4D546864;
pub const MTRK: u32 = 0x4D54726B;
/// The largest delta time or length a variable-length quantity holds (4 bytes).
pub const VLQ_MAX: u32 = 0x0FFFFFFF;

/// `v` as 4 big-endian bytes.
pub fn push_u32_be(ref out: Array<u8>, v: u32) {
    let (b3, rest) = DivRem::div_rem(v, 0x1000000);
    let (b2, rest) = DivRem::div_rem(rest, 0x10000);
    let (b1, b0) = DivRem::div_rem(rest, 0x100);
    out.append(b3.try_into().unwrap());
    out.append(b2.try_into().unwrap());
    out.append(b1.try_into().unwrap());
    out.append(b0.try_into().unwrap());
}

/// `v` as a MIDI variable-length quantity: 7 bits per byte, most significant first, the high bit
/// set on every byte but the last.
///
/// Nearly every delta is 1 or 2 bytes, so those two are straight-line code. The longer forms are a
/// loop on purpose: a call to a function without a loop is charged for its most expensive path
/// whichever one it takes, which would make a 1 byte quantity cost as much as a 4 byte one.
pub fn push_vlq(ref out: Array<u8>, v: u32) {
    if v < 0x80 {
        out.append(v.try_into().unwrap());
    } else if v < 0x4000 {
        let (high, low) = DivRem::div_rem(v, 0x80);
        out.append((0x80 + high).try_into().unwrap());
        out.append(low.try_into().unwrap());
    } else {
        assert(v <= VLQ_MAX, 'midi: vlq too large');
        // the 7-bit groups above the lowest, from the top: three in 4 bytes, two in 3 bytes. What
        // is left of `rest` is below `place * 0x80`, so each group fits 7 bits.
        let mut place: u32 = if v >= 0x200000 {
            0x200000
        } else {
            0x4000
        };
        let mut rest = v;
        while place > 1 {
            let (group, below) = DivRem::div_rem(rest, place.try_into().unwrap());
            out.append((0x80 + group).try_into().unwrap());
            rest = below;
            place /= 0x80;
        }
        out.append(rest.try_into().unwrap());
    }
}

/// A chunk: 4-byte tag, 4-byte big-endian length, body.
pub fn push_chunk(ref out: Array<u8>, tag: u32, body: Span<u8>) {
    push_u32_be(ref out, tag);
    push_u32_be(ref out, body.len());
    out.append_span(body);
}

/// The `MThd` chunk body (`format`, track count, `division`), after the checks every file writer
/// makes.
// On purpose (CASM size and gas): inlined, the checks fold away where `format` and `division` are
// constants, as in the composer's calls; otherwise each call runs them.
#[inline(always)]
fn header_body(format: u16, division: u16, n: usize) -> Array<u8> {
    assert(format <= 2, 'midi: format');
    assert(format != 0 || n == 1, 'midi: format 0 has one track');
    assert(division > 0 && division < 0x8000, 'midi: division');
    assert(n < 0x10000, 'midi: too many tracks');
    array![
        (format / 256).try_into().unwrap(), (format % 256).try_into().unwrap(),
        (n / 256).try_into().unwrap(), (n % 256).try_into().unwrap(),
        (division / 256).try_into().unwrap(), (division % 256).try_into().unwrap(),
    ]
}

/// A whole file: the `MThd` header (`format` 0, 1 or 2, the track count, `division` ticks per
/// quarter note) and one `MTrk` chunk per track body, in order.
pub fn smf_bytes(format: u16, division: u16, tracks: Span<Array<u8>>) -> Array<u8> {
    let header = header_body(format, division, tracks.len());
    let mut out: Array<u8> = array![];
    push_chunk(ref out, MTHD, header.span());
    for track in tracks {
        push_chunk(ref out, MTRK, track.span());
    }
    out
}

/// A chunk's 4-byte tag and 4-byte big-endian length.
fn chunk_head(tag: u32, len: usize) -> Array<u8> {
    let mut head: Array<u8> = array![];
    push_u32_be(ref head, tag);
    push_u32_be(ref head, len);
    head
}

/// `smf_bytes` as a `ByteArray` (what `bytes_to_byte_array` makes of it), read once: the track
/// bodies are packed where they are instead of being copied into one array first.
pub fn smf_byte_array(format: u16, division: u16, tracks: Span<Array<u8>>) -> ByteArray {
    let header = header_body(format, division, tracks.len());
    let mthd = chunk_head(MTHD, header.len());
    let mut chunks: Array<Span<u8>> = array![mthd.span(), header.span()];
    for track in tracks {
        let mtrk = chunk_head(MTRK, track.len());
        chunks.append(mtrk.span());
        chunks.append(track.span());
    }
    chunks_to_byte_array(chunks.span())
}

/// A track body under construction.
#[derive(Drop)]
pub struct TrackWriter {
    data: Array<u8>,
    /// Time of the last event, in ticks.
    time: u32,
    /// Omit a channel message's status byte when it repeats the previous one.
    running: bool,
    /// The status in effect for running status (0: none; meta events clear it).
    status: u8,
}

#[generate_trait]
pub impl TrackWriterImpl of TrackWriterTrait {
    /// A writer that writes every status byte.
    fn new() -> TrackWriter {
        TrackWriter { data: array![], time: 0, running: false, status: 0 }
    }

    /// A writer that uses running status: a channel message with the same status as the one
    /// before it is written without its status byte (smaller files for drum tracks and the like).
    fn with_running_status() -> TrackWriter {
        TrackWriter { data: array![], time: 0, running: true, status: 0 }
    }

    /// Time of the last event written.
    fn time(self: @TrackWriter) -> u32 {
        self.time
    }

    fn is_empty(self: @TrackWriter) -> bool {
        self.data.len() == 0
    }

    /// The delta to `time`, which becomes the track's time.
    fn delta(ref self: TrackWriter, time: u32) {
        let (elapsed, backwards) = time.overflowing_sub(self.time);
        assert(!backwards, 'midi: time goes backwards');
        push_vlq(ref self.data, elapsed);
        self.time = time;
    }

    /// A channel message's status byte, unless running status makes it implicit.
    fn status(ref self: TrackWriter, status: u8) {
        if !(self.running && status == self.status) {
            self.data.append(status);
        }
        self.status = status;
    }

    /// A channel message with two data bytes (note off/on, aftertouch, control, pitch bend).
    // Shared by authored and generated tracks; keep one encoder rather than specializing every
    // call.
    #[inline(never)]
    fn message(ref self: TrackWriter, time: u32, status: u8, data1: u8, data2: u8) {
        self.delta(time);
        self.status(status);
        self.data.append(data1);
        self.data.append(data2);
    }

    /// A channel message with one data byte (program change, channel pressure).
    fn message1(ref self: TrackWriter, time: u32, status: u8, data1: u8) {
        self.delta(time);
        self.status(status);
        self.data.append(data1);
    }

    fn note_on(ref self: TrackWriter, time: u32, channel: u8, key: u8, velocity: u8) {
        self.message(time, 0x90 + channel % 16, key, velocity);
    }

    fn note_off(ref self: TrackWriter, time: u32, channel: u8, key: u8, velocity: u8) {
        self.message(time, 0x80 + channel % 16, key, velocity);
    }

    fn program(ref self: TrackWriter, time: u32, channel: u8, program: u8) {
        self.message1(time, 0xC0 + channel % 16, program);
    }

    #[inline(never)]
    fn control(ref self: TrackWriter, time: u32, channel: u8, controller: u8, value: u8) {
        self.message(time, 0xB0 + channel % 16, controller, value);
    }

    /// A meta event (`FF kind length data`). Clears running status.
    #[inline(never)]
    fn meta(ref self: TrackWriter, time: u32, kind: u8, data: Span<u8>) {
        self.delta(time);
        self.data.append(0xFF);
        self.data.append(kind);
        push_vlq(ref self.data, data.len());
        self.data.append_span(data);
        self.status = 0;
    }

    /// Set Tempo: microseconds per quarter note (24 bits).
    fn tempo(ref self: TrackWriter, time: u32, us_per_quarter: u32) {
        assert(us_per_quarter < 0x1000000, 'midi: tempo');
        let data: Array<u8> = array![
            (us_per_quarter / 0x10000).try_into().unwrap(),
            ((us_per_quarter / 0x100) % 256).try_into().unwrap(),
            (us_per_quarter % 256).try_into().unwrap(),
        ];
        self.meta(time, 0x51, data.span());
    }

    /// The track body, closed with End of Track at the last event.
    fn finish(self: TrackWriter) -> Array<u8> {
        let time = self.time;
        self.finish_at(time)
    }

    /// The track body, closed with End of Track at `time`, or at the last event if that is later.
    /// A player that loops to the latest End of Track (onchain-midi-player) then loops at `time`.
    #[inline(never)]
    fn finish_at(mut self: TrackWriter, time: u32) -> Array<u8> {
        let end = if time > self.time {
            time
        } else {
            self.time
        };
        self.meta(end, 0x2F, [].span());
        self.data
    }
}

#[cfg(test)]
mod encoding_tests {
    use super::{VLQ_MAX, push_u32_be, push_vlq};

    /// `push_vlq` as it was before the 1 and 2 byte forms got their own code: one formula for all
    /// four lengths.
    fn formula_vlq(v: u32) -> Array<u8> {
        assert(v <= VLQ_MAX, 'midi: vlq too large');
        let mut out: Array<u8> = array![];
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
        out
    }

    fn assert_same(v: u32) {
        let mut out: Array<u8> = array![];
        push_vlq(ref out, v);
        assert(out == formula_vlq(v), 'vlq differs');
    }

    /// `edge` and its neighbours.
    fn assert_same_around(edge: u32) {
        assert_same(edge - 1);
        assert_same(edge);
        assert_same(edge + 1);
    }

    #[test]
    fn matches_the_formula_at_every_length_boundary() {
        assert_same(0);
        assert_same(1);
        assert_same_around(0x80);
        assert_same(0x7F);
        assert_same_around(0x4000);
        assert_same(0x3FFF);
        assert_same_around(0x200000);
        assert_same(0x1FFFFF);
        assert_same(VLQ_MAX - 1);
        assert_same(VLQ_MAX);
    }

    /// Every value of 1 and 2 bytes, and the start of 3.
    #[test]
    #[available_gas(1000000000000)]
    fn matches_the_formula_below_0x4100() {
        let mut v: u32 = 0;
        while v < 0x4100 {
            assert_same(v);
            v += 1;
        }
    }

    /// A deterministic spread over the whole range: each value a third more than the last, plus
    /// 129.
    #[test]
    #[available_gas(1000000000000)]
    fn matches_the_formula_across_the_range() {
        let mut v: u32 = 1;
        while v <= VLQ_MAX {
            assert_same(v);
            v += v / 3 + 129;
        }
    }

    #[test]
    #[should_panic(expected: ('midi: vlq too large',))]
    fn rejects_one_past_the_largest() {
        let mut out: Array<u8> = array![];
        push_vlq(ref out, VLQ_MAX + 1);
    }

    #[test]
    #[should_panic(expected: ('midi: vlq too large',))]
    fn rejects_the_largest_u32() {
        let mut out: Array<u8> = array![];
        push_vlq(ref out, 0xFFFFFFFF);
    }

    #[test]
    fn u32_be_is_the_four_bytes_most_significant_first() {
        let mut out: Array<u8> = array![];
        push_u32_be(ref out, 0);
        push_u32_be(ref out, 0x01020304);
        push_u32_be(ref out, 0xFF00FF00);
        push_u32_be(ref out, 0x4D546864);
        push_u32_be(ref out, 0xFFFFFFFF);
        assert_eq!(
            out,
            array![
                0, 0, 0, 0, 1, 2, 3, 4, 0xFF, 0, 0xFF, 0, 0x4D, 0x54, 0x68, 0x64, 0xFF, 0xFF, 0xFF,
                0xFF,
            ],
        );
    }
}
