//! Bytes out of a contract.

/// 31 bytes as one big-endian word. Straight-line: a loop pays a recursive call and a gas check per
/// byte, this is two steps a byte.
#[cairofmt::skip]
fn pack_word(chunk: Box<[u8; 31]>) -> felt252 {
    let [
        b0, b1, b2, b3, b4, b5, b6, b7,
        b8, b9, b10, b11, b12, b13, b14, b15,
        b16, b17, b18, b19, b20, b21, b22, b23,
        b24, b25, b26, b27, b28, b29, b30,
    ] = chunk.unbox();
    let word: felt252 = b0.into();
    let word = word * 0x100 + b1.into();
    let word = word * 0x100 + b2.into();
    let word = word * 0x100 + b3.into();
    let word = word * 0x100 + b4.into();
    let word = word * 0x100 + b5.into();
    let word = word * 0x100 + b6.into();
    let word = word * 0x100 + b7.into();
    let word = word * 0x100 + b8.into();
    let word = word * 0x100 + b9.into();
    let word = word * 0x100 + b10.into();
    let word = word * 0x100 + b11.into();
    let word = word * 0x100 + b12.into();
    let word = word * 0x100 + b13.into();
    let word = word * 0x100 + b14.into();
    let word = word * 0x100 + b15.into();
    let word = word * 0x100 + b16.into();
    let word = word * 0x100 + b17.into();
    let word = word * 0x100 + b18.into();
    let word = word * 0x100 + b19.into();
    let word = word * 0x100 + b20.into();
    let word = word * 0x100 + b21.into();
    let word = word * 0x100 + b22.into();
    let word = word * 0x100 + b23.into();
    let word = word * 0x100 + b24.into();
    let word = word * 0x100 + b25.into();
    let word = word * 0x100 + b26.into();
    let word = word * 0x100 + b27.into();
    let word = word * 0x100 + b28.into();
    let word = word * 0x100 + b29.into();
    let word = word * 0x100 + b30.into();
    word
}

/// Fewer than 31 bytes as one big-endian word (the pending word of a `ByteArray`).
fn pack_tail(mut bytes: Span<u8>) -> felt252 {
    let mut word: felt252 = 0;
    while let Option::Some(byte) = bytes.pop_front() {
        word = word * 0x100 + (*byte).into();
    }
    word
}

/// Packs bytes into a ByteArray 31 bytes per word with felt arithmetic, then deserializes it.
/// Several times cheaper than appending byte by byte.
pub fn bytes_to_byte_array(mut bytes: Span<u8>) -> ByteArray {
    let mut serialized: Array<felt252> = array![(bytes.len() / 31).into()];
    while let Option::Some(chunk) = bytes.multi_pop_front::<31>() {
        serialized.append(pack_word(*chunk));
    }
    serialized.append(pack_tail(bytes));
    serialized.append(bytes.len().into());
    let mut span = serialized.span();
    Serde::deserialize(ref span).unwrap()
}

/// `bytes_to_byte_array` of the chunks end to end, without copying them into one array first. A
/// word that straddles two chunks is carried over: `pending` holds its first `pending_len` bytes.
pub fn chunks_to_byte_array(chunks: Span<Span<u8>>) -> ByteArray {
    // The serialized `ByteArray` opens with its word count, so the whole length is needed first.
    let mut total: usize = 0;
    for chunk in chunks {
        total += chunk.len();
    }
    let mut serialized: Array<felt252> = array![(total / 31).into()];
    let mut pending: felt252 = 0;
    let mut pending_len: usize = 0;
    for chunk in chunks {
        let mut bytes = *chunk;
        loop {
            // Whole words while no word is carried, then byte by byte: the end of the carried
            // word, or fewer than 31 bytes to carry.
            if pending_len == 0 {
                if let Option::Some(words) = bytes.multi_pop_front::<31>() {
                    serialized.append(pack_word(*words));
                    continue;
                }
            }
            let Option::Some(byte) = bytes.pop_front() else {
                break;
            };
            pending = pending * 0x100 + (*byte).into();
            pending_len += 1;
            if pending_len == 31 {
                serialized.append(pending);
                pending = 0;
                pending_len = 0;
            }
        }
    }
    serialized.append(pending);
    serialized.append(pending_len.into());
    let mut span = serialized.span();
    Serde::deserialize(ref span).unwrap()
}

/// `[byte_len, words...]`: each word packs up to 31 bytes big-endian (the last one fewer, not
/// padded). The RPC transport for Beast views; decoded by `bytesToFelts`'s inverse in
/// offchain/beast-sound.
pub fn to_felt252_array(mut bytes: Span<u8>) -> Array<felt252> {
    let mut out: Array<felt252> = array![bytes.len().into()];
    while let Option::Some(chunk) = bytes.multi_pop_front::<31>() {
        out.append(pack_word(*chunk));
    }
    if bytes.len() != 0 {
        out.append(pack_tail(bytes));
    }
    out
}
