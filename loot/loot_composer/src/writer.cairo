//! A track writer for the engines' MIDI: the same bytes as Beast Sound v1.1.0's
//! `midi::smf::TrackWriter` as the engines use it (every status byte written, no running status),
//! without its panic paths (CASM size: a panic-free writer spares an error branch at each of its many
//! call sites). Times never go backwards here and deltas stay below 2^28, as `midi` asserts; a delta
//! that did go backwards would be written as 0 rather than revert.
use crate::common::u32_of;

#[derive(Drop)]
pub struct TrackWriter {
    data: Array<u8>,
    /// Time of the last event, in ticks.
    time: u32,
}

/// `x` (below 256) as a byte.
#[inline(always)]
pub fn byte(x: felt252) -> u8 {
    match x.try_into() {
        Option::Some(b) => b,
        Option::None => 0,
    }
}

/// `v` (below 2^28) as a variable-length quantity, without a loop.
#[inline(never)]
fn push_vlq(ref out: Array<u8>, v: u32) {
    if v < 0x80 {
        out.append(byte(v.into()));
        return;
    }
    let (q1, g0) = DivRem::div_rem(v, 0x80);
    if q1 != 0 {
        let (q2, g1) = DivRem::div_rem(q1, 0x80);
        if q2 != 0 {
            let (g3, g2) = DivRem::div_rem(q2, 0x80);
            if g3 != 0 {
                out.append(byte(0x80 + g3.into()));
            }
            out.append(byte(0x80 + g2.into()));
        }
        out.append(byte(0x80 + g1.into()));
    }
    out.append(byte(g0.into()));
}

#[generate_trait]
pub impl TrackWriterImpl of TrackWriterTrait {
    fn new() -> TrackWriter {
        TrackWriter { data: array![], time: 0 }
    }

    /// The delta to `time`, which becomes the track's time.
    #[inline(always)]
    fn delta(ref self: TrackWriter, time: u32) {
        push_vlq(ref self.data, u32_of(time.into() - self.time.into()));
        self.time = time;
    }

    /// A channel message with two data bytes.
    #[inline(never)]
    fn message(ref self: TrackWriter, time: u32, status: u8, data1: u8, data2: u8) {
        self.delta(time);
        self.data.append(status);
        self.data.append(data1);
        self.data.append(data2);
    }

    /// A channel message with one data byte.
    fn message1(ref self: TrackWriter, time: u32, status: u8, data1: u8) {
        self.delta(time);
        self.data.append(status);
        self.data.append(data1);
    }

    fn note_on(ref self: TrackWriter, time: u32, channel: u8, key: u8, velocity: u8) {
        self.message(time, byte(0x90 + channel.into()), key, velocity);
    }

    fn note_off(ref self: TrackWriter, time: u32, channel: u8, key: u8, velocity: u8) {
        self.message(time, byte(0x80 + channel.into()), key, velocity);
    }

    fn program(ref self: TrackWriter, time: u32, channel: u8, program: u8) {
        self.message1(time, byte(0xC0 + channel.into()), program);
    }

    fn control(ref self: TrackWriter, time: u32, channel: u8, controller: u8, value: u8) {
        self.message(time, byte(0xB0 + channel.into()), controller, value);
    }

    /// A meta event (`FF kind length data`), data shorter than 128 bytes.
    #[inline(never)]
    fn meta(ref self: TrackWriter, time: u32, kind: u8, data: Span<u8>) {
        self.delta(time);
        self.data.append(0xFF);
        self.data.append(kind);
        self.data.append(byte(data.len().into()));
        self.data.append_span(data);
    }

    /// Set Tempo: microseconds per quarter note (24 bits).
    fn tempo(ref self: TrackWriter, time: u32, us: u32) {
        let (a, r) = DivRem::div_rem(us, 0x10000);
        let (b, c) = DivRem::div_rem(r, 0x100);
        self.meta(time, 0x51, [byte(a.into()), byte(b.into()), byte(c.into())].span());
    }

    /// The track body, closed with End of Track at `time`, or at the last event if that is later.
    #[inline(never)]
    fn finish_at(mut self: TrackWriter, time: u32) -> Array<u8> {
        let end = if time > self.time {
            time
        } else {
            self.time
        };
        self.delta(end);
        self.data.append(0xFF);
        self.data.append(0x2F);
        self.data.append(0);
        self.data
    }
}
