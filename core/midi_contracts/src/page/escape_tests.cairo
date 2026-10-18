//! `append_escaped` against the byte-by-byte definition it replaces, over word boundaries, the
//! pending word, bytes next to '%' and '#', and every alignment of the output it appends to.

use super::{HASHES, PERCENTS, append_escaped, has_byte};

/// `s` escaped one byte at a time: '%' → %25, '#' → %23.
fn escaped_by_byte(s: @ByteArray) -> ByteArray {
    let mut out: ByteArray = Default::default();
    for i in 0..s.len() {
        let c = s[i];
        if c == '%' {
            out.append(@"%25");
        } else if c == '#' {
            out.append(@"%23");
        } else {
            out.append_byte(c);
        }
    }
    out
}

/// `n` copies of `byte`.
fn repeated(n: usize, byte: u8) -> ByteArray {
    let mut s: ByteArray = Default::default();
    for _ in 0..n {
        s.append_byte(byte);
    }
    s
}

/// `n` copies of `fill`, with `special` at index `at`.
fn with_byte_at(n: usize, fill: u8, at: usize, special: u8) -> ByteArray {
    let mut s: ByteArray = Default::default();
    for i in 0..n {
        s.append_byte(if i == at {
            special
        } else {
            fill
        });
    }
    s
}

/// `append_escaped` onto an output that already holds `prefix_len` bytes.
fn check(prefix_len: usize, s: @ByteArray) {
    let mut out = repeated(prefix_len, 'p');
    append_escaped(ref out, s);
    let mut expected = repeated(prefix_len, 'p');
    expected.append(@escaped_by_byte(s));
    assert_eq!(out, expected);
}

#[test]
fn escapes_nothing_in_empty_and_clean_input() {
    check(0, @"");
    check(28, @"");
    for n in array![1, 30, 31, 32, 62, 93, 94] {
        check(0, @repeated(n, 'a'));
        check(28, @repeated(n, 'a'));
    }
}

#[test]
fn escapes_a_special_at_every_word_edge() {
    for n in array![1, 2, 30, 31, 32, 33, 61, 62, 63, 64, 92, 93, 94] {
        for at in array![0, 1, 15, 16, 29, 30, 31, 32, 33, 46, 47, 60, 61, 62, 63, 92, 93] {
            if at < n {
                for special in array!['%', '#'] {
                    check(28, @with_byte_at(n, 'a', at, special));
                }
            }
        }
    }
}

#[test]
fn escapes_inputs_made_only_of_specials() {
    for n in array![1, 2, 30, 31, 32, 62, 63, 93, 94] {
        check(28, @repeated(n, '%'));
        check(0, @repeated(n, '#'));
    }
    // A lone special as the pending word, after a full word of special-free bytes.
    check(28, @with_byte_at(32, 'a', 31, '#'));
    check(28, @with_byte_at(32, 'a', 31, '%'));
}

#[test]
fn escapes_at_every_output_alignment() {
    // 31 full-word offsets of the output, a special in the first word, one in the pending word.
    let s = with_byte_at(70, 'a', 40, '#');
    let mut t = with_byte_at(70, 'b', 3, '%');
    t.append_byte('#');
    for prefix_len in 0..32_usize {
        check(prefix_len, @s);
        check(prefix_len, @t);
        check(prefix_len, @with_byte_at(31, 'a', 30, '%'));
        check(prefix_len, @with_byte_at(31, 'a', 0, '#'));
    }
}

/// Bytes that a bit trick for '%' (0x25) and '#' (0x23) could confuse with them.
fn adversarial(i: u128) -> u8 {
    let bytes: Array<u8> = array![
        '%', '#', 'a', '"', '$', '&', '!', '\'', 0, 0x7f, 0x80, 0xa3, 0xa5, 0xff, '2', '5', 0x01,
        0x24, 0x26, 0x22,
    ];
    *bytes[(i % bytes.len().into()).try_into().unwrap()]
}

#[test]
fn escapes_like_the_definition_on_adversarial_bytes() {
    let mut state: u128 = 12345;
    for length in 0..140_usize {
        let mut s: ByteArray = Default::default();
        for _ in 0..length {
            // 64-bit LCG; the high bits are the ones with a long period.
            state = (state * 6364136223846793005 + 1442695040888963407) % 0x10000000000000000;
            s.append_byte(adversarial(state / 0x100000000));
        }
        check(28, @s);
        check(length % 31, @s);
    }
}

#[test]
fn has_byte_is_exact_for_every_byte_in_every_lane_position() {
    let fills: Array<u128> = array![0, 0xff, 0x80, 0x7f, 0x24, 0x26, 0xa5, 0x25, 0x23];
    let ones: u128 = 0x01010101010101010101010101010101;
    let mut place: u128 = 1; // 256^pos
    for pos in 0..16_u32 {
        for fill in fills.span() {
            for b in 0..256_u128 {
                // 16 bytes of `fill`, with byte `pos` (counting from the low end) replaced by `b`.
                let v = *fill * ones - *fill * place + b * place;
                assert_eq!(has_byte(v, PERCENTS), b == 0x25 || *fill == 0x25);
                assert_eq!(has_byte(v, HASHES), b == 0x23 || *fill == 0x23);
            }
        }
        if pos < 15 {
            place *= 0x100;
        }
    }
}
