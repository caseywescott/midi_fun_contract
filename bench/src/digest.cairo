//! Output digests and the check against the expected table. Computed in the test body, outside
//! the measured call, and independently of the code under test (no `midi::pack`).

use core::poseidon::poseidon_hash_span;

/// `[byte_len, 31-byte big-endian words..., the last partial word if any]`: the layout of
/// `midi::pack::to_felt252_array` and of the JS engine's `bytesToFelts`, taken here from the
/// ByteArray's own serialization `[word_count, words..., pending_word, pending_len]`.
pub fn byte_array_felts(b: @ByteArray) -> Array<felt252> {
    let mut ser: Array<felt252> = array![];
    b.serialize(ref ser);
    let words: u32 = (*ser.at(0)).try_into().unwrap();
    let pending_len: u32 = (*ser.at(words + 2)).try_into().unwrap();
    let mut out: Array<felt252> = array![(words * 31 + pending_len).into()];
    let mut i: u32 = 1;
    while i <= words {
        out.append(*ser.at(i));
        i += 1;
    }
    if pending_len > 0 {
        out.append(*ser.at(words + 1));
    }
    out
}

/// The same layout for raw bytes.
pub fn u8s_felts(bytes: Span<u8>) -> Array<felt252> {
    let mut out: Array<felt252> = array![bytes.len().into()];
    let mut word: felt252 = 0;
    let mut n: u32 = 0;
    for b in bytes {
        word = word * 0x100 + (*b).into();
        n += 1;
        if n == 31 {
            out.append(word);
            word = 0;
            n = 0;
        }
    }
    if n > 0 {
        out.append(word);
    }
    out
}

/// `(byte_len, poseidon(byte_array_felts))`: the digest of a MIDI file or any other bytes, the one
/// `scripts/genesis_parity.mjs` compares (`poseidonHashMany(bytesToFelts(bytes))`).
pub fn bytes_digest(b: @ByteArray) -> (u32, felt252) {
    (b.len(), poseidon_hash_span(byte_array_felts(b).span()))
}

pub fn u8s_digest(bytes: Span<u8>) -> (u32, felt252) {
    (bytes.len(), poseidon_hash_span(u8s_felts(bytes).span()))
}

/// `(felt_count, poseidon(felts))` of a value's Serde serialization.
pub fn serde_digest<T, +Serde<T>, +Drop<T>>(value: @T) -> (u32, felt252) {
    let mut felts: Array<felt252> = array![];
    value.serialize(ref felts);
    (felts.len(), poseidon_hash_span(felts.span()))
}

/// Asserts `got` is the expected `(len, hash)` of `key`; the failure names the case.
#[cfg(not(feature: 'record'))]
pub fn check(key: ByteArray, got: (u32, felt252), expected: (u32, felt252)) {
    let (len, hash) = got;
    let (exp_len, exp_hash) = expected;
    assert!(
        len == exp_len && hash == exp_hash,
        "DIGEST MISMATCH {}: got ({}, {}), expected ({}, {})",
        key,
        len,
        hash,
        exp_len,
        exp_hash,
    );
}

/// Record mode (`--features record`, `gas_bench.py freeze` only): prints the digest instead of
/// checking it.
#[cfg(feature: 'record')]
pub fn check(key: ByteArray, got: (u32, felt252), expected: (u32, felt252)) {
    let (len, hash) = got;
    println!("EXPECT {} {} {}", key, len, hash);
}
