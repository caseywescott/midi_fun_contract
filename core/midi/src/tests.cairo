use crate::pack::{bytes_to_byte_array, to_felt252_array};
use crate::smf::{TrackWriterTrait, push_vlq, smf_bytes};

fn vlq(v: u32) -> Array<u8> {
    let mut out = array![];
    push_vlq(ref out, v);
    out
}

#[test]
fn vlq_matches_the_spec_examples() {
    // The examples table of the Standard MIDI File specification.
    assert_eq!(vlq(0), array![0x00]);
    assert_eq!(vlq(0x40), array![0x40]);
    assert_eq!(vlq(0x7F), array![0x7F]);
    assert_eq!(vlq(0x80), array![0x81, 0x00]);
    assert_eq!(vlq(0x2000), array![0xC0, 0x00]);
    assert_eq!(vlq(0x3FFF), array![0xFF, 0x7F]);
    assert_eq!(vlq(0x4000), array![0x81, 0x80, 0x00]);
    assert_eq!(vlq(0x100000), array![0xC0, 0x80, 0x00]);
    assert_eq!(vlq(0x1FFFFF), array![0xFF, 0xFF, 0x7F]);
    assert_eq!(vlq(0x200000), array![0x81, 0x80, 0x80, 0x00]);
    assert_eq!(vlq(0x8000000), array![0xC0, 0x80, 0x80, 0x00]);
    assert_eq!(vlq(0xFFFFFFF), array![0xFF, 0xFF, 0xFF, 0x7F]);
}

#[test]
#[should_panic(expected: ('midi: vlq too large',))]
fn vlq_rejects_more_than_28_bits() {
    vlq(0x10000000);
}

#[test]
fn track_writes_deltas_and_end_of_track() {
    let mut t = TrackWriterTrait::new();
    t.tempo(0, 500000);
    t.program(0, 2, 33);
    t.control(0, 2, 10, 64);
    t.note_on(480, 2, 60, 100);
    t.note_off(960, 2, 60, 64);
    assert_eq!(t.time(), 960);
    assert_eq!(
        t.finish_at(1920),
        array![
            0, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20, // tempo 500000
            0, 0xC2, 33, // program
            0, 0xB2, 10,
            64, // pan
            0x83, 0x60, 0x92, 60, 100, // +480 note on
            0x83, 0x60, 0x82, 60,
            64, // +480 note off
            0x87, 0x40, 0xFF, 0x2F, 0 // End of Track at 1920
        ],
    );
}

#[test]
fn finish_never_moves_end_of_track_before_the_last_event() {
    let mut t = TrackWriterTrait::new();
    t.note_on(100, 0, 60, 1);
    assert_eq!(t.finish_at(50), array![100, 0x90, 60, 1, 0, 0xFF, 0x2F, 0]);
    let mut u = TrackWriterTrait::new();
    u.note_on(100, 0, 60, 1);
    assert_eq!(u.finish(), array![100, 0x90, 60, 1, 0, 0xFF, 0x2F, 0]);
}

#[test]
fn running_status_omits_repeated_status_bytes() {
    let mut t = TrackWriterTrait::with_running_status();
    t.note_on(0, 9, 36, 120);
    t.note_on(0, 9, 42, 80);
    t.note_on(240, 9, 42, 52);
    t.note_off(240, 9, 42, 0); // a new status is written
    t.note_off(250, 9, 36, 0);
    t.meta(250, 0x01, array!['a'].span()); // a meta event clears running status
    t.note_off(250, 9, 38, 0);
    assert_eq!(
        t.finish(),
        array![
            0, 0x99, 36, 120, 0, 42, 80, 0x81, 0x70, 42, 52, 0, 0x89, 42, 0, 10, 36, 0, 0, 0xFF, 1,
            1, 'a', 0, 0x89, 38, 0, 0, 0xFF, 0x2F, 0,
        ],
    );
    // Without it, every status byte is written.
    let mut w = TrackWriterTrait::new();
    w.note_on(0, 9, 36, 120);
    w.note_on(0, 9, 42, 80);
    assert_eq!(w.finish(), array![0, 0x99, 36, 120, 0, 0x99, 42, 80, 0, 0xFF, 0x2F, 0]);
}

#[test]
#[should_panic(expected: ('midi: time goes backwards',))]
fn track_rejects_time_going_backwards() {
    let mut t = TrackWriterTrait::new();
    t.note_on(10, 0, 60, 1);
    t.note_off(9, 0, 60, 0);
}

#[test]
fn smf_bytes_writes_header_and_chunks() {
    let file = smf_bytes(1, 480, array![array![0, 0xFF, 0x2F, 0], array![1, 2]].span());
    assert_eq!(
        file,
        array![
            0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, 2, 0x01, 0xE0, // MThd
            0x4D, 0x54, 0x72,
            0x6B, 0, 0, 0, 4, 0, 0xFF, 0x2F, 0, // MTrk
            0x4D, 0x54, 0x72, 0x6B, 0, 0, 0, 2, 1, 2,
        ],
    );
}

#[test]
#[should_panic(expected: ('midi: format 0 has one track',))]
fn smf_bytes_format_0_has_one_track() {
    smf_bytes(0, 480, array![array![], array![]].span());
}

fn byte_at(i: usize) -> u8 {
    ((i * 37 + 11) % 256).try_into().unwrap()
}

#[test]
fn bytes_to_byte_array_matches_append_byte() {
    // Every pending length (0..30) and the full-word boundaries around 31 and 62.
    let mut n: usize = 0;
    while n <= 100 {
        let mut bytes: Array<u8> = array![];
        let mut expected: ByteArray = Default::default();
        let mut i: usize = 0;
        while i < n {
            bytes.append(byte_at(i));
            expected.append_byte(byte_at(i));
            i += 1;
        }
        assert_eq!(bytes_to_byte_array(bytes.span()), expected);
        n += 1;
    }
}

#[test]
fn to_felt252_array_packs_31_bytes_per_word() {
    assert_eq!(to_felt252_array([].span()), array![0]);
    assert_eq!(to_felt252_array([1, 2].span()), array![2, 0x0102]);
    let mut bytes: Array<u8> = array![];
    let mut i: usize = 0;
    while i < 33 {
        bytes.append(byte_at(i));
        i += 1;
    }
    let felts = to_felt252_array(bytes.span());
    assert_eq!(felts.len(), 3);
    assert_eq!(*felts.at(0), 33);
    let mut first: felt252 = 0;
    let mut j: usize = 0;
    while j < 31 {
        first = first * 0x100 + byte_at(j).into();
        j += 1;
    }
    assert_eq!(*felts.at(1), first);
    assert_eq!(*felts.at(2), byte_at(31).into() * 0x100 + byte_at(32).into());
}

/// The README example.
#[test]
fn readme_example() {
    let mut tempo = TrackWriterTrait::new();
    tempo.tempo(0, 500000);
    let mut lead = TrackWriterTrait::new();
    lead.program(0, 0, 80);
    lead.control(0, 0, 10, 32);
    lead.note_on(0, 0, 60, 100);
    lead.note_off(480, 0, 60, 64);
    let mut drums = TrackWriterTrait::with_running_status();
    drums.note_on(0, 9, 36, 120);
    drums.note_on(480, 9, 38, 100);
    let file: Array<u8> = smf_bytes(
        1, 480, array![tempo.finish_at(1920), lead.finish(), drums.finish_at(1920)].span(),
    );
    // MThd 14 + tempo 8+12 + lead 8+20 + drums 8+13 (the second hit without its status byte)
    assert_eq!(file.len(), 83);
    assert_eq!(*file.at(11), 3);
}
