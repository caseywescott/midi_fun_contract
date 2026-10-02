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
//! token_uri is plain JSON (`data:application/json;utf8,…`), not base64, so the JSON and SVG are
//! never re-encoded (see onchain/page.js):
//!
//!   'data:application/json;utf8,{' ++ escape(members)
//!     ++ ',"image":"data:image/svg+xml;base64,' ++ svg_b64 ++ '",' ++ <spaces>
//!     ++ '"animation_url":"data:text/html;base64,'
//!     ++ stored_segment()                       (the page, base64 at build time, word-aligned)
//!     ++ b64(b64(midi) <spaces> '</script><script type="text/plain" id="art">')
//!     ++ svg_b64 ++ '"}'
//!
//! So the per-call base64 work is the MIDI, twice. escape() writes '%' as %25 and '#' as %23.

use starknet::ContractAddress;

pub mod b64;
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

/// D: base64 of the MIDI, space padding, then `midi_close()`. 3n bytes, so its base64 has no '='
/// and the SVG base64 can follow. The padding sits inside the MIDI block, where the player
/// ignores whitespace.
pub fn midi_html(midi: @ByteArray) -> ByteArray {
    let close = midi_close();
    let mut d: ByteArray = Default::default();
    append_base64(ref d, midi);
    pad_spaces(ref d, 3, close.len());
    d.append(@close);
    d
}

// Base64 lives in b64.cairo: reads input as 31-byte words, 93 bytes per step, through a 12-bit table.
pub use b64::{append_base64, base64};

/// The complete token_uri for already-composed MIDI. `members` is the JSON object body without
/// braces and without `image`, e.g. `"name":"Warlock","description":"...","attributes":[...]`.
/// `svg_b64` is base64 of the token's SVG (what `image` carries after
/// `data:image/svg+xml;base64,`).
/// `midi` is a Standard MIDI File.
pub fn token_uri(members: @ByteArray, svg_b64: @ByteArray, midi: @ByteArray) -> ByteArray {
    let url_key: ByteArray = "\"animation_url\":\"data:text/html;base64,";
    let mut out: ByteArray = "data:application/json;utf8,{";
    append_escaped(ref out, members);
    out.append(@",\"image\":\"data:image/svg+xml;base64,");
    out.append(svg_b64);
    out.append(@"\",");
    // JSON whitespace until the stored page starts on a 31-byte word boundary (cheap to append).
    pad_spaces(ref out, 31, url_key.len());
    out.append(@url_key);
    out.append(@page_data::stored_segment());
    append_base64(ref out, @midi_html(midi));
    out.append(svg_b64);
    out.append(@"\"}");
    out
}

/// Append `s` with '%' → %25 and '#' → %23 (JSON data URIs must not carry them raw).
fn append_escaped(ref out: ByteArray, s: @ByteArray) {
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
