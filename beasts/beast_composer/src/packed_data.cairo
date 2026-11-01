//! Shared reader for generated tables packed as seven little-endian u32 values per felt.
//! Editions and synth settings deliberately use the same format and decoder.

#[derive(Drop)]
pub struct Reader {
    pub data: Span<felt252>,
    pub pos: u32,
    pub word: u256,
    pub left: u32,
}

/// The next 32-bit table value. This is the unchanged reader previously emitted by both generators.
#[inline(never)]
pub fn read(ref r: Reader) -> u32 {
    if r.left == 0 {
        r.word = (*r.data.at(r.pos)).into();
        r.pos += 1;
        r.left = 7;
    }
    let (q, v) = DivRem::div_rem(r.word, 0x100000000);
    r.word = q;
    r.left -= 1;
    v.try_into().unwrap()
}

#[cfg(test)]
mod tests {
    use super::{Reader, read};

    #[test]
    fn read_values_and_word_boundary() {
        let data = array![0x7000000060000000500000004000000030000000200000001, 0xffffffff];
        let mut r = Reader { data: data.span(), pos: 0, word: 0, left: 0 };
        for expected in 1_u32..8 {
            assert(read(ref r) == expected, 'packed table order');
        }
        assert(read(ref r) == 0xffffffff, 'packed next word');
        assert(read(ref r) == 0, 'packed zero padding');
    }

    #[test]
    fn read_maximum_fields_from_nonzero_position() {
        let data = array![0, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffff];
        let mut r = Reader { data: data.span(), pos: 1, word: 0, left: 0 };
        for _ in 0_u32..7 {
            assert(read(ref r) == 0xffffffff, 'packed maximum field');
        }
        assert(r.left == 0 && r.pos == 2, 'packed cursor');
    }
}
