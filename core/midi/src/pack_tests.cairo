//! `to_felt252_array`: the byte count, then 31-byte big-endian words.

use crate::pack::to_felt252_array;

#[test]
fn to_felt252_array_empty() {
    let bytes = array![];
    let felts = to_felt252_array(bytes.span());
    assert!(felts.len() == 1, "empty midi: only length felt");
    assert!(*felts.at(0) == 0.into(), "byte count 0");
}

#[test]
fn to_felt252_array_four_bytes_one_chunk() {
    let bytes = array![0x4d_u8, 0x54_u8, 0x68_u8, 0x64_u8];
    let felts = to_felt252_array(bytes.span());
    assert!(felts.len() == 2, "len felt + one payload");
    assert!(*felts.at(0) == 4.into(), "byte count");
    let expected: u256 = 0x4d_u256 * 256_u256 * 256_u256 * 256_u256
        + 0x54_u256 * 256_u256 * 256_u256
        + 0x68_u256 * 256_u256
        + 0x64_u256;
    assert!(*felts.at(1) == expected.try_into().unwrap(), "packed chunk");
}

#[test]
fn to_felt252_array_32_bytes_two_payloads() {
    let mut bytes: Array<u8> = ArrayTrait::new();
    let mut k: u8 = 0;
    loop {
        if k >= 32 {
            break;
        }
        bytes.append(k);
        k += 1;
    }
    let felts = to_felt252_array(bytes.span());
    assert!(felts.len() == 3, "count + 31 + 1");
    assert!(*felts.at(0) == 32.into(), "byte count");
}

// `bytes_to_byte_array` and `to_felt252_array` against the byte-by-byte loops they replaced and,
// for the ByteArray, against corelib's own `append_byte`.

use crate::pack::bytes_to_byte_array;

/// `len` bytes, none repeating its neighbour, with 0x00 and 0xFF among them.
fn sample(len: u32) -> Array<u8> {
    let mut bytes = array![];
    let mut i: u32 = 0;
    while i != len {
        bytes.append(((i * 37 + i / 31 + 255) % 256).try_into().unwrap());
        i += 1;
    }
    bytes
}

fn byte_array_by_append(mut bytes: Span<u8>) -> ByteArray {
    let mut out: ByteArray = "";
    while let Option::Some(byte) = bytes.pop_front() {
        out.append_byte(*byte);
    }
    out
}

/// The packing loops this module had before `pop_word`.
fn felts_by_loop(mut bytes: Span<u8>) -> Array<felt252> {
    let mut out: Array<felt252> = array![bytes.len().into()];
    while bytes.len() != 0 {
        let mut word: felt252 = 0;
        let mut k: u32 = 31;
        while k != 0 {
            match bytes.pop_front() {
                Option::Some(b) => { word = word * 0x100 + (*b).into(); },
                Option::None => { break; },
            }
            k -= 1;
        }
        out.append(word);
    }
    out
}

#[test]
fn packers_match_the_byte_loops_at_every_length_to_100() {
    let mut len: u32 = 0;
    while len != 101 {
        let bytes = sample(len);
        assert!(
            bytes_to_byte_array(bytes.span()) == byte_array_by_append(bytes.span()), "bytearray",
        );
        assert!(to_felt252_array(bytes.span()) == felts_by_loop(bytes.span()), "felts");
        len += 1;
    }
}

#[test]
fn packers_match_the_byte_loops_around_word_multiples() {
    // Multiples of 31 and their neighbours, up to the size of the largest Genesis Track (7,197).
    let mut words: u32 = 3;
    while words < 240 {
        let mut len = words * 31 - 1;
        while len != words * 31 + 2 {
            let bytes = sample(len);
            assert!(
                bytes_to_byte_array(bytes.span()) == byte_array_by_append(bytes.span()),
                "bytearray",
            );
            assert!(to_felt252_array(bytes.span()) == felts_by_loop(bytes.span()), "felts");
            len += 1;
        }
        words *= 3;
    }
    let bytes = sample(7197);
    assert!(bytes_to_byte_array(bytes.span()) == byte_array_by_append(bytes.span()), "7197");
    assert!(to_felt252_array(bytes.span()) == felts_by_loop(bytes.span()), "7197 felts");
}

#[test]
fn packers_keep_extreme_bytes() {
    // Words of all 0x00 and of all 0xFF (the largest bytes31), then a mix, with a tail.
    let mut bytes: Array<u8> = array![];
    let mut i: u32 = 0;
    while i != 31 {
        bytes.append(0);
        i += 1;
    }
    while i != 62 {
        bytes.append(0xFF);
        i += 1;
    }
    bytes.append(0xFF);
    bytes.append(0);
    let ba = bytes_to_byte_array(bytes.span());
    assert!(ba == byte_array_by_append(bytes.span()), "bytearray");
    assert!(ba.len() == 64, "len");
    let felts = to_felt252_array(bytes.span());
    assert!(felts == felts_by_loop(bytes.span()), "felts");
    assert!(*felts.at(1) == 0, "zero word");
    assert!(*felts.at(3) == 0xFF00, "tail");
}

// `chunks_to_byte_array` against `bytes_to_byte_array` of the same bytes in one piece.

use crate::pack::chunks_to_byte_array;

/// `bytes` cut at the (ascending) `cuts`, packed as chunks and as one array.
fn packs_alike(bytes: Span<u8>, cuts: Span<u32>) {
    let mut chunks: Array<Span<u8>> = array![];
    let mut from: u32 = 0;
    for cut in cuts {
        chunks.append(bytes.slice(from, *cut - from));
        from = *cut;
    }
    chunks.append(bytes.slice(from, bytes.len() - from));
    assert!(chunks_to_byte_array(chunks.span()) == bytes_to_byte_array(bytes), "chunks");
}

#[test]
fn chunks_of_nothing_are_empty() {
    let none: Array<Span<u8>> = array![];
    assert!(chunks_to_byte_array(none.span()) == bytes_to_byte_array(array![].span()), "none");
    let empties: Array<Span<u8>> = array![array![].span(), array![].span()];
    assert!(chunks_to_byte_array(empties.span()) == "", "empties");
}

#[test]
fn chunks_match_one_array_cut_in_two_anywhere() {
    let mut len: u32 = 0;
    while len != 71 {
        let bytes = sample(len);
        let mut at: u32 = 0;
        while at <= len {
            packs_alike(bytes.span(), array![at].span());
            at += 1;
        }
        len += 1;
    }
}

#[test]
fn chunks_match_one_array_cut_in_three() {
    let lens = array![1_u32, 30, 31, 32, 62, 93, 100];
    for len in lens {
        let bytes = sample(len);
        let mut first: u32 = 0;
        while first <= len {
            let mut second = first;
            while second <= len {
                packs_alike(bytes.span(), array![first, second].span());
                second += 3;
            }
            packs_alike(bytes.span(), array![first, len].span());
            first += 1;
        }
    }
}

#[test]
fn chunks_match_one_array_cut_every_byte() {
    let bytes = sample(100);
    let mut cuts: Array<u32> = array![];
    let mut at: u32 = 1;
    while at != 100 {
        cuts.append(at);
        at += 1;
    }
    packs_alike(bytes.span(), cuts.span());
}

#[test]
fn chunks_match_one_array_cut_like_a_midi_file() {
    // 14-byte header, then 8-byte chunk heads before bodies of every length class.
    let bytes = sample(7197);
    packs_alike(
        bytes.span(), array![8, 14, 22, 52, 60, 91, 99, 4000, 4008, 4038, 7000, 7197].span(),
    );
    packs_alike(bytes.span(), array![8, 14, 22, 7197].span());
    packs_alike(bytes.span(), array![31, 62, 93, 124, 3100].span());
}
