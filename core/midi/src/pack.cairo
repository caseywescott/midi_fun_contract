//! Bytes out of a contract.

/// Packs bytes into a ByteArray 31 bytes per word with felt arithmetic, then deserializes it.
/// Several times cheaper than appending byte by byte.
pub fn bytes_to_byte_array(mut bytes: Span<u8>) -> ByteArray {
    let mut full_words = bytes.len() / 31;
    let mut serialized: Array<felt252> = array![full_words.into()];
    while full_words != 0 {
        let mut word: felt252 = 0;
        let mut k: usize = 31;
        while k != 0 {
            word = word * 0x100 + (*bytes.pop_front().unwrap()).into();
            k -= 1;
        }
        serialized.append(word);
        full_words -= 1;
    }
    let pending_len = bytes.len();
    let mut pending: felt252 = 0;
    while let Option::Some(byte) = bytes.pop_front() {
        pending = pending * 0x100 + (*byte).into();
    }
    serialized.append(pending);
    serialized.append(pending_len.into());
    let mut span = serialized.span();
    Serde::deserialize(ref span).unwrap()
}

/// `[byte_len, words...]`: each word packs up to 31 bytes big-endian (the last one fewer, not
/// padded). The RPC transport of Koji's views; decoded by `bytesToFelts`'s inverse in
/// offchain/beast-sound.
pub fn to_felt252_array(mut bytes: Span<u8>) -> Array<felt252> {
    let mut out: Array<felt252> = array![bytes.len().into()];
    while bytes.len() != 0 {
        let mut word: felt252 = 0;
        let mut k: usize = 31;
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
