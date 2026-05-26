#[cfg(test)]
mod tests {
    use core::array::ArrayTrait;
    use core::traits::TryInto;
    use koji::midi::output::to_felt252_array;

    #[test]
    fn to_felt252_array_empty() {
        let bytes = array![];
        let felts = to_felt252_array(bytes);
        assert!(felts.len() == 1, "empty midi: only length felt");
        assert!(*felts.at(0) == 0.into(), "byte count 0");
    }

    #[test]
    fn to_felt252_array_four_bytes_one_chunk() {
        let bytes = array![0x4d_u8, 0x54_u8, 0x68_u8, 0x64_u8];
        let felts = to_felt252_array(bytes);
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
        };
        let felts = to_felt252_array(bytes);
        assert!(felts.len() == 3, "count + 31 + 1");
        assert!(*felts.at(0) == 32.into(), "byte count");
    }
}
