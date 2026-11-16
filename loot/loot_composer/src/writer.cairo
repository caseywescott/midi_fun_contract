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
    /// 0, or (one felt, so the writer stays small): bit 0 STATS, bit 1 SHIFT, the pitch sum at 2^2, the
    /// count at 2^34, the open keys at 2^50 (bit k for key k). With STATS the writer keeps the sum and
    /// count of the notes the lab's `notesOf` finds in this (one channel) track: a note on (velocity
    /// above 0) closed by the next note off or zero-velocity note on of its key. With SHIFT every note
    /// (on, off, aftertouch) of a pitched channel is an octave lower, held to 0..127 (the lab's
    /// `lifted` t: an edition's accompaniment an octave lower).
    pub x: felt252,
}

pub const STATS: felt252 = 1;
pub const SHIFT: felt252 = 2;
const SUM1: felt252 = 4;
const COUNT1: felt252 = 0x400000000;
const OPEN1: felt252 = 0x4000000000000;

/// 2^k for k below 128 (no loop, no panic path).
#[inline(never)]
fn bit(k: u8) -> felt252 {
    let (h, l) = DivRem::div_rem(k, 16);
    let lo: felt252 = match LOW16.span().get(l.into()) {
        Option::Some(x) => *x.unbox(),
        Option::None => 0,
    };
    let hi: felt252 = match HIGH16.span().get(h.into()) {
        Option::Some(x) => *x.unbox(),
        Option::None => 0,
    };
    lo * hi
}

const LOW16: [felt252; 16] = [
    1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768,
];
const HIGH16: [felt252; 8] = [
    1, 0x10000, 0x100000000, 0x1000000000000, 0x10000000000000000, 0x100000000000000000000,
    0x1000000000000000000000000, 0x10000000000000000000000000000,
];

/// `x` (below 256) as a byte.
#[inline(always)]
pub fn byte(x: felt252) -> u8 {
    match x.try_into() {
        Option::Some(b) => b,
        Option::None => 0,
    }
}

/// `v` (below 2^28) as a variable-length quantity: 1 and 2 bytes straight-line, the longer forms a
/// loop (as `midi::smf::push_vlq`: a loop-free function is charged for its longest path).
#[inline(never)]
fn push_vlq(ref out: Array<u8>, v: u32) {
    if v < 0x80 {
        out.append(byte(v.into()));
    } else if v < 0x4000 {
        let (h, l) = DivRem::div_rem(v, 0x80);
        out.append(byte(0x80 + h.into()));
        out.append(byte(l.into()));
    } else {
        let mut place: u32 = if v >= 0x200000 {
            0x200000
        } else {
            0x4000
        };
        let mut rest = v;
        while place > 1 {
            let (group, below) = DivRem::div_rem(rest, place.try_into().unwrap());
            out.append(byte(0x80 + group.into()));
            rest = below;
            place /= 0x80;
        }
        out.append(byte(rest.into()));
    }
}

#[generate_trait]
pub impl TrackWriterImpl of TrackWriterTrait {
    fn new() -> TrackWriter {
        TrackWriter { data: array![], time: 0, x: 0 }
    }

    /// A note event under `x` (see the field): the key moved (SHIFT), the notes counted (STATS).
    #[inline(never)]
    fn note_x(ref self: TrackWriter, status: u8, key: u8, velocity: u8) -> u8 {
        let xl: u256 = self.x.into();
        let (_, flags) = DivRem::div_rem(xl.low, 4);
        let (ty, ch) = DivRem::div_rem(status, 16);
        let (shift, stats) = DivRem::div_rem(flags, 2);
        let mut key = key;
        if shift == 1 && ty >= 8 && ty <= 10 && ch != 9 {
            key = if key < 12 {
                0
            } else {
                key - 12
            };
        }
        if stats == 1 && (ty == 8 || ty == 9) {
            let b = bit(key) * OPEN1;
            let bb: u256 = b.into();
            let nz: NonZero<u256> = match bb.try_into() {
                Option::Some(n) => n,
                Option::None => { return key; },
            };
            let (q, _) = DivRem::div_rem(xl, nz);
            let (_, odd) = DivRem::div_rem(q.low, 2);
            if ty == 9 && velocity != 0 {
                if odd == 0 {
                    self.x += b;
                }
            } else if odd == 1 {
                self.x += SUM1 * key.into() + COUNT1 - b;
            }
        }
        key
    }

    /// The pitch sum and count STATS kept.
    fn stats(self: @TrackWriter) -> (felt252, felt252) {
        let xl: u256 = self.x.into();
        let (_, low) = DivRem::div_rem(xl.low, 0x4000000000000);
        let (count, rest) = DivRem::div_rem(low, 0x400000000);
        let (sum, _) = DivRem::div_rem(rest, 4);
        (sum.into(), count.into())
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
        let data1 = if self.x != 0 && status < 0xB0 {
            self.note_x(status, data1, data2)
        } else {
            data1
        };
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
