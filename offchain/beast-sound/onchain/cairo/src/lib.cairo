//! TinySynth sound page: an NFT's `token_uri` with its music as `animation_url`, built onchain.
//!
//! The NFT keeps building its JSON members and SVG exactly as today, then calls
//! `token_uri(members, svg_b64, token_address, token_id)` here instead of base64-encoding the JSON
//! itself. The page asks its configured `IMidiProvider` for the token's MIDI (the provider reads
//! whatever state it composes from) and returns the full token_uri. `animation_url` is an HTML
//! page:
//! the TinySynth player (stored in this contract's code), the MIDI as base64 text, and the same
//! SVG.
//! The browser plays it on tap; nothing is fetched and the player knows nothing about the
//! collection.
//!
//! Every piece is aligned to 3 bytes so base64 runs concatenate (see onchain/page.js):
//!
//!   "data:application/json;base64,"
//!     ++ b64('{' members ',' <spaces> '"image":"data:image/svg+xml;base64,')
//!     ++ b64(S) where S = svg_b64 '"' <spaces>          (encoded once, appended twice)
//!     ++ b64(',  ')
//!     ++ stored_segment()                               (the page, encoded at build time)
//!     ++ b64(b64(b64(midi) <spaces> '</script><script type="text/plain" id="art">'))
//!     ++ b64(S)
//!     ++ b64('}')
//!
//! So the per-call base64 work is today's (members and SVG) plus the MIDI, three times.

use starknet::ContractAddress;

pub mod page_data;

fn pad_spaces(ref s: ByteArray, multiple: usize, extra: usize) {
    while (s.len() + extra) % multiple != 0 {
        s.append_byte(' ');
    }
}

/// Closes the MIDI block and opens the inert block that carries the SVG (the SVG may use XML-only
/// syntax, so the page shows it through an <img> instead of inlining it).
fn midi_close() -> ByteArray {
    "</script><script type=\"text/plain\" id=\"art\">"
}

/// D: base64 of the MIDI, space padding, then `midi_close()`. 9n bytes, so its base64 is whole
/// 3-byte groups. The padding sits inside the MIDI block, where the player ignores whitespace.
pub fn midi_html(midi: @ByteArray) -> ByteArray {
    let close = midi_close();
    let mut d: ByteArray = Default::default();
    append_base64(ref d, midi);
    pad_spaces(ref d, 9, close.len());
    d.append(@close);
    d
}

fn base64_chars() -> Span<u8> {
    array![
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
        'G',
        'H',
        'I',
        'J',
        'K',
        'L',
        'M',
        'N',
        'O',
        'P',
        'Q',
        'R',
        'S',
        'T',
        'U',
        'V',
        'W',
        'X',
        'Y',
        'Z',
        'a',
        'b',
        'c',
        'd',
        'e',
        'f',
        'g',
        'h',
        'i',
        'j',
        'k',
        'l',
        'm',
        'n',
        'o',
        'p',
        'q',
        'r',
        's',
        't',
        'u',
        'v',
        'w',
        'x',
        'y',
        'z',
        '0',
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
        '8',
        '9',
        '+',
        '/',
    ]
        .span()
}

fn pow256(n: usize) -> NonZero<u128> {
    let table: [u128; 16] = [
        0x1, 0x100, 0x10000, 0x1000000, 0x100000000, 0x10000000000, 0x1000000000000,
        0x100000000000000, 0x10000000000000000, 0x1000000000000000000, 0x100000000000000000000,
        0x10000000000000000000000, 0x1000000000000000000000000, 0x100000000000000000000000000,
        0x10000000000000000000000000000, 0x1000000000000000000000000000000,
    ];
    (*table.span().at(n)).try_into().unwrap()
}

/// Four base64 characters for a 24-bit group, as one big-endian word.
#[inline(always)]
fn encode_group(group: u32, t: Span<u8>) -> felt252 {
    let (high, low) = DivRem::div_rem(group, 0x1000_u32.try_into().unwrap());
    let (c0, c1) = DivRem::div_rem(high, 0x40_u32.try_into().unwrap());
    let (c2, c3) = DivRem::div_rem(low, 0x40_u32.try_into().unwrap());
    let c0: felt252 = (*t[c0]).into();
    let c1: felt252 = (*t[c1]).into();
    let c2: felt252 = (*t[c2]).into();
    let c3: felt252 = (*t[c3]).into();
    c0 * 0x1000000 + c1 * 0x10000 + c2 * 0x100 + c3
}

/// Up to two input bytes waiting for the rest of their 3-byte group.
#[derive(Drop, Copy)]
struct Carry {
    value: u32,
    len: usize,
}

/// Encodes `n` (<= 16) big-endian bytes held in `v`, after any carried bytes. Whole groups come
/// off the bottom of `v` with one division each and are appended as one word.
fn encode_chunk(ref out: ByteArray, ref carry: Carry, mut v: u128, mut n: usize, t: Span<u8>) {
    if carry.len != 0 {
        // n >= 1 for every caller, so only (carry 1 byte, n = 1) can fall short of a group.
        let need = 3 - carry.len;
        if n < need {
            carry.value = carry.value * 0x100 + v.try_into().unwrap();
            carry.len += n;
            return;
        }
        let (top, rest) = DivRem::div_rem(v, pow256(n - need));
        let group = carry.value * (if need == 1 {
            0x100
        } else {
            0x10000
        })
            + top.try_into().unwrap();
        out.append_word(encode_group(group, t), 4);
        v = rest;
        n -= need;
    }
    let tail = n % 3;
    let (mut body, low) = DivRem::div_rem(v, pow256(tail));
    carry = Carry { value: low.try_into().unwrap(), len: tail };
    let groups = n / 3;
    if groups == 0 {
        return;
    }
    // Groups come out last-first; each lands 4 characters further left.
    let mut word: felt252 = 0;
    let mut shift: felt252 = 1;
    let mut k = groups;
    while k != 0 {
        let (rest, group) = DivRem::div_rem(body, 0x1000000_u128.try_into().unwrap());
        word += encode_group(group.try_into().unwrap(), t) * shift;
        shift *= 0x100000000;
        body = rest;
        k -= 1;
    }
    out.append_word(word, groups * 4);
}

/// Standard base64 (RFC 4648, with '=' padding), appended to `out`. Reads `input` a ByteArray word
/// (15 + 16 bytes) at a time instead of byte by byte: about 3.4x cheaper than indexing.
pub fn append_base64(ref out: ByteArray, input: @ByteArray) {
    let t = base64_chars();
    let mut serialized: Array<felt252> = array![];
    input.serialize(ref serialized);
    let mut words = serialized.span();
    let mut full_words: usize = (*words.pop_front().unwrap()).try_into().unwrap();
    let mut carry = Carry { value: 0, len: 0 };
    while full_words != 0 {
        let u256 { low, high } = (*words.pop_front().unwrap()).into();
        encode_chunk(ref out, ref carry, high, 15, t);
        encode_chunk(ref out, ref carry, low, 16, t);
        full_words -= 1;
    }
    let u256 { low, high } = (*words.pop_front().unwrap()).into();
    let pending_len: usize = (*words.pop_front().unwrap()).try_into().unwrap();
    if pending_len > 16 {
        encode_chunk(ref out, ref carry, high, pending_len - 16, t);
        encode_chunk(ref out, ref carry, low, 16, t);
    } else if pending_len != 0 {
        encode_chunk(ref out, ref carry, low, pending_len, t);
    }
    if carry.len == 1 {
        let b0 = carry.value;
        let c0: felt252 = (*t[b0 / 4]).into();
        let c1: felt252 = (*t[(b0 % 4) * 16]).into();
        out.append_word(c0 * 0x1000000 + c1 * 0x10000 + '=' * 0x100 + '=', 4);
    } else if carry.len == 2 {
        let (b0, b1) = DivRem::div_rem(carry.value, 0x100_u32.try_into().unwrap());
        let c0: felt252 = (*t[b0 / 4]).into();
        let c1: felt252 = (*t[(b0 % 4) * 16 + b1 / 16]).into();
        let c2: felt252 = (*t[(b1 % 16) * 4]).into();
        out.append_word(c0 * 0x1000000 + c1 * 0x10000 + c2 * 0x100 + '=', 4);
    }
}

pub fn base64(input: @ByteArray) -> ByteArray {
    let mut out: ByteArray = Default::default();
    append_base64(ref out, input);
    out
}

/// The complete token_uri for already-composed MIDI. `members` is the JSON object body without
/// braces and without `image`, e.g. `"name":"Warlock","description":"...","attributes":[...]`.
/// `svg_b64` is base64 of the token's SVG (what `image` carries after
/// `data:image/svg+xml;base64,`).
/// `midi` is a Standard MIDI File.
pub fn token_uri(members: @ByteArray, svg_b64: @ByteArray, midi: @ByteArray) -> ByteArray {
    let image_key: ByteArray = "\"image\":\"data:image/svg+xml;base64,";
    let mut a: ByteArray = "{";
    a.append(members);
    a.append_byte(',');
    pad_spaces(ref a, 3, image_key.len());
    a.append(@image_key);

    let mut s = svg_b64.clone();
    s.append_byte('"');
    pad_spaces(ref s, 3, 0);
    let s_b64 = base64(@s);

    let mut out: ByteArray = "data:application/json;base64,";
    append_base64(ref out, @a);
    out.append(@s_b64);
    append_base64(ref out, @",  ");
    out.append(@page_data::stored_segment());
    append_base64(ref out, @base64(@midi_html(midi)));
    out.append(@s_b64);
    append_base64(ref out, @"}");
    out
}

#[starknet::interface]
pub trait IMidiSoundPage<T> {
    /// The token's full token_uri with `animation_url`. `members` and `svg_b64` are as for the
    /// pure `token_uri`; the MIDI comes from the provider's `get_midi(token_address, token_id)`.
    fn token_uri(
        self: @T,
        members: ByteArray,
        svg_b64: ByteArray,
        token_address: ContractAddress,
        token_id: u256,
    ) -> ByteArray;
    fn get_midi_provider(self: @T) -> ContractAddress;
}

/// The player lives in this contract's code; the provider is fixed at deploy. A new player or
/// orchestration is a new class, a new provider a new deployment.
#[starknet::contract]
pub mod MidiSoundPage {
    use core::num::traits::Zero;
    use midi_provider::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};

    #[storage]
    struct Storage {
        midi_provider: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, midi_provider: ContractAddress) {
        assert(midi_provider.is_non_zero(), 'zero midi provider');
        self.midi_provider.write(midi_provider);
    }

    #[abi(embed_v0)]
    impl MidiSoundPageImpl of super::IMidiSoundPage<ContractState> {
        fn token_uri(
            self: @ContractState,
            members: ByteArray,
            svg_b64: ByteArray,
            token_address: ContractAddress,
            token_id: u256,
        ) -> ByteArray {
            let midi = IMidiProviderDispatcher { contract_address: self.midi_provider.read() }
                .get_midi(token_address, token_id);
            super::token_uri(@members, @svg_b64, @midi)
        }

        fn get_midi_provider(self: @ContractState) -> ContractAddress {
            self.midi_provider.read()
        }
    }
}

#[cfg(test)]
mod contract_tests;
#[cfg(test)]
mod tests;
