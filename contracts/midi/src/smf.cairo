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

pub const MTHD: u32 = 0x4D546864;
pub const MTRK: u32 = 0x4D54726B;
/// The largest delta time or length a variable-length quantity holds (4 bytes).
pub const VLQ_MAX: u32 = 0x0FFFFFFF;

/// `v` as 4 big-endian bytes.
pub fn push_u32_be(ref out: Array<u8>, v: u32) {
    out.append(((v / 0x1000000) % 256).try_into().unwrap());
    out.append(((v / 0x10000) % 256).try_into().unwrap());
    out.append(((v / 0x100) % 256).try_into().unwrap());
    out.append((v % 256).try_into().unwrap());
}

/// `v` as a MIDI variable-length quantity: 7 bits per byte, most significant first, the high bit
/// set on every byte but the last.
pub fn push_vlq(ref out: Array<u8>, v: u32) {
    assert(v <= VLQ_MAX, 'midi: vlq too large');
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

/// A chunk: 4-byte tag, 4-byte big-endian length, body.
pub fn push_chunk(ref out: Array<u8>, tag: u32, body: Span<u8>) {
    push_u32_be(ref out, tag);
    push_u32_be(ref out, body.len());
    out.append_span(body);
}

/// A whole file: the `MThd` header (`format` 0, 1 or 2, the track count, `division` ticks per
/// quarter note) and one `MTrk` chunk per track body, in order.
pub fn smf_bytes(format: u16, division: u16, tracks: Span<Array<u8>>) -> Array<u8> {
    assert(format <= 2, 'midi: format');
    assert(format != 0 || tracks.len() == 1, 'midi: format 0 has one track');
    assert(division > 0 && division < 0x8000, 'midi: division');
    let n = tracks.len();
    assert(n < 0x10000, 'midi: too many tracks');
    let mut out: Array<u8> = array![];
    let header: Array<u8> = array![
        (format / 256).try_into().unwrap(),
        (format % 256).try_into().unwrap(),
        (n / 256).try_into().unwrap(),
        (n % 256).try_into().unwrap(),
        (division / 256).try_into().unwrap(),
        (division % 256).try_into().unwrap(),
    ];
    push_chunk(ref out, MTHD, header.span());
    for track in tracks {
        push_chunk(ref out, MTRK, track.span());
    }
    out
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
        assert(time >= self.time, 'midi: time goes backwards');
        push_vlq(ref self.data, time - self.time);
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

    fn control(ref self: TrackWriter, time: u32, channel: u8, controller: u8, value: u8) {
        self.message(time, 0xB0 + channel % 16, controller, value);
    }

    /// A meta event (`FF kind length data`). Clears running status.
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
    /// A player that loops to the latest End of Track (onchain-tinysynth) then loops at `time`.
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
