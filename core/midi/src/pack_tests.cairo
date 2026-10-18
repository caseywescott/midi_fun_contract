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
