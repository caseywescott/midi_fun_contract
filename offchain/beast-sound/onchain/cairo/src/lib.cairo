//! Beast Sound page: a Beast's `token_uri` with its theme as `animation_url`, built onchain.
//!
//! The Beasts NFT keeps building its JSON members and animated SVG exactly as today, then calls
//! `token_uri(members, svg_b64, token_id, live)` here instead of base64-encoding the JSON itself.
//! `animation_url` is an HTML page: the composer script (stored in this contract's code), one line
//! of per-token inputs, and the same SVG. The browser composes the theme from the inputs with
//! engine v1 and plays it on tap; nothing is fetched.
//!
//! token_uri is plain JSON (`data:application/json;utf8,…`), not base64: Cairo base64 costs ~70K
//! L2 gas per byte, and encoding the whole JSON is the biggest cost of today's token_uri. Only the
//! page inside animation_url is base64, and nearly all of it was encoded at build time:
//!
//!   'data:application/json;utf8,{' ++ escape(members)
//!     ++ ',"image":"data:image/svg+xml;base64,' ++ svg_b64 ++ '",' ++ <spaces>
//!     ++ '"animation_url":"data:text/html;base64,'
//!     ++ HEAD ++ MODULE_1 ++ … ++ MODULE_n               (stored, word-aligned by the spaces)
//!     ++ b64(inputs or notes line)                       (~100 bytes: the only per-call encoding)
//!     ++ svg_b64 ++ '"}'
//!
//! escape() writes '%' as %25 and '#' as %23, the two characters a JSON data URI cannot carry raw.

//!
//! The library is split into modules (core, beast, music, midi, synth, play, fx, api, page), each in
//! its own contract (`modules.cairo`) exposing its segment, base64(<script>…</script>).
//! `BeastSoundPage` keeps the page HEAD and a fixed list of module contracts, and splices
//! HEAD ++ every module segment into animation_url. Other projects can reuse any module contract.

pub mod modules;
pub mod page_data;

/// A stored library module: its name and its segment, base64(<script>…</script>) padded so segments
/// concatenate at word boundaries. Decode a segment once to get the module's script.
#[starknet::interface]
pub trait IBeastSoundModule<T> {
    fn name(self: @T) -> felt252;
    fn segment(self: @T) -> ByteArray;
}

/// Live stats the composer reads (same fields and types as koji's `BeastV3LiveState`).
#[derive(Copy, Drop, Serde, PartialEq, Debug)]
pub struct BeastSoundInputs {
    pub adventurers_killed: u64,
    pub scars: u64,
    pub summit_held_seconds: u64,
    pub rank: u16,
    pub species_count: u16,
}

fn pad_spaces(ref s: ByteArray, multiple: usize, extra: usize) {
    while (s.len() + extra) % multiple != 0 {
        s.append_byte(' ');
    }
}

/// `<script>BEAST_SOUND="token,kills,scars,held,rank,count"</script>`, then the opening of the inert
/// text block that carries the SVG (the Beasts SVG uses XML-only syntax, so the page shows it through
/// an <img> instead of inlining it). Space-padded to 9n bytes so its base64 is whole 3-byte groups.
pub fn inputs_html(token_id: u256, live: BeastSoundInputs) -> ByteArray {
    let art_open: ByteArray = "<script type=\"text/plain\" id=\"art\">";
    let mut s: ByteArray = "<script>BEAST_SOUND=\"";
    s
        .append(
            @format!(
                "{},{},{},{},{},{}",
                token_id,
                live.adventurers_killed,
                live.scars,
                live.summit_held_seconds,
                live.rank,
                live.species_count,
            ),
        );
    s.append(@"\"</script>");
    pad_spaces(ref s, 3, art_open.len());
    s.append(@art_open);
    s
}

/// `<script>BEAST_NOTES="0x…,0x…"</script>` (BSN1 felts, e.g. from the Cairo composer's
/// get_score_notes), then the opening of the SVG text block, space-padded to 9n bytes.
pub fn notes_html(felts: Span<felt252>) -> ByteArray {
    let art_open: ByteArray = "<script type=\"text/plain\" id=\"art\">";
    let mut s: ByteArray = "<script>BEAST_NOTES=\"";
    for i in 0..felts.len() {
        if i > 0 {
            s.append_byte(',');
        }
        let v: u256 = (*felts[i]).into();
        s.append(@format!("0x{:x}", v));
    }
    s.append(@"\"</script>");
    pad_spaces(ref s, 3, art_open.len());
    s.append(@art_open);
    s
}

fn base64_chars() -> Span<u8> {
    array![
        'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R',
        'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z', 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
        'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', '0', '1',
        '2', '3', '4', '5', '6', '7', '8', '9', '+', '/',
    ]
        .span()
}

/// Standard base64 (RFC 4648, with '=' padding), appended to `out`.
pub fn append_base64(ref out: ByteArray, input: @ByteArray) {
    let t = base64_chars();
    let len = input.len();
    let mut i = 0;
    while i + 3 <= len {
        let n: u32 = input[i].into() * 0x10000 + input[i + 1].into() * 0x100 + input[i + 2].into();
        out.append_byte(*t[n / 0x40000]);
        out.append_byte(*t[(n / 0x1000) % 64]);
        out.append_byte(*t[(n / 0x40) % 64]);
        out.append_byte(*t[n % 64]);
        i += 3;
    }
    let rest = len - i;
    if rest > 0 {
        let b1: u32 = if rest == 2 {
            input[i + 1].into()
        } else {
            0
        };
        let n: u32 = input[i].into() * 0x10000 + b1 * 0x100;
        out.append_byte(*t[n / 0x40000]);
        out.append_byte(*t[(n / 0x1000) % 64]);
        out.append_byte(if rest == 2 {
            *t[(n / 0x40) % 64]
        } else {
            '='
        });
        out.append_byte('=');
    }
}

pub fn base64(input: @ByteArray) -> ByteArray {
    let mut out: ByteArray = Default::default();
    append_base64(ref out, input);
    out
}

/// The complete token_uri. `members` is the JSON object body without braces and without `image`,
/// e.g. `"name":"Warlock","description":"...","attributes":[...]`. `svg_b64` is base64 of the
/// Beast's SVG (what the NFT puts after `data:image/svg+xml;base64,` today).
/// HEAD plus every module segment from this package, in load order (no contract calls). This is what
/// `BeastSoundPage` assembles from its module contracts.
pub fn stored_local() -> ByteArray {
    let mut stored = page_data::head_segment();
    stored.append(@modules::all_segments());
    stored
}

/// The complete token_uri for the inputs page (the library composes from token ID + stats), given the
/// stored segment (HEAD ++ module segments).
pub fn token_uri(
    members: @ByteArray,
    svg_b64: @ByteArray,
    token_id: u256,
    live: BeastSoundInputs,
    stored: @ByteArray,
) -> ByteArray {
    token_uri_with_line(members, svg_b64, @inputs_html(token_id, live), stored)
}

/// The complete token_uri around one per-token line (`inputs_html` or `notes_html`).
pub fn token_uri_with_line(
    members: @ByteArray, svg_b64: @ByteArray, line: @ByteArray, stored: @ByteArray,
) -> ByteArray {
    let url_key: ByteArray = "\"animation_url\":\"data:text/html;base64,";
    let mut out: ByteArray = "data:application/json;utf8,{";
    append_escaped(ref out, members);
    out.append(@",\"image\":\"data:image/svg+xml;base64,");
    out.append(svg_b64);
    out.append(@"\",");
    // JSON whitespace until the stored library starts on a 31-byte word boundary (cheap to append).
    pad_spaces(ref out, 31, url_key.len());
    out.append(@url_key);
    out.append(stored);
    append_base64(ref out, line);
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
pub trait IBeastSoundPage<T> {
    /// The Beast's full token_uri with `animation_url` (see module docs for the arguments).
    fn token_uri(
        self: @T, members: ByteArray, svg_b64: ByteArray, token_id: u256, live: BeastSoundInputs,
    ) -> ByteArray;
    /// The module contracts this page splices in, in load order.
    fn modules(self: @T) -> Array<starknet::ContractAddress>;
}

/// The page: HEAD in code plus a module list fixed at deploy. A different library version or module
/// set is a new page contract, so a Beast's music never changes under it.
#[starknet::contract]
pub mod BeastSoundPage {
    use starknet::ContractAddress;
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use super::{BeastSoundInputs, IBeastSoundModuleDispatcher, IBeastSoundModuleDispatcherTrait};

    #[storage]
    struct Storage {
        modules: Vec<ContractAddress>,
    }

    #[constructor]
    fn constructor(ref self: ContractState, modules: Array<ContractAddress>) {
        assert(modules.len() > 0, 'no modules');
        for m in modules {
            self.modules.push(m);
        }
    }

    #[abi(embed_v0)]
    impl BeastSoundPageImpl of super::IBeastSoundPage<ContractState> {
        fn token_uri(
            self: @ContractState,
            members: ByteArray,
            svg_b64: ByteArray,
            token_id: u256,
            live: BeastSoundInputs,
        ) -> ByteArray {
            let mut stored = super::page_data::head_segment();
            for i in 0..self.modules.len() {
                let module = IBeastSoundModuleDispatcher { contract_address: self.modules.at(i).read() };
                stored.append(@module.segment());
            }
            super::token_uri(@members, @svg_b64, token_id, live, @stored)
        }

        fn modules(self: @ContractState) -> Array<ContractAddress> {
            let mut out = array![];
            for i in 0..self.modules.len() {
                out.append(self.modules.at(i).read());
            }
            out
        }
    }
}

/// The Cairo composer (contracts/beast_sound `BeastSoundComposer`): engine v1 computed onchain.
/// `BeastSoundInputs` serializes exactly like its `BeastV3LiveState`.
#[starknet::interface]
pub trait IBeastSoundComposer<T> {
    fn get_score_notes(self: @T, token_id: u256, live: BeastSoundInputs) -> Array<felt252>;
    fn get_score_instructions(self: @T, token_id: u256, live: BeastSoundInputs) -> Array<felt252>;
}

/// Notes page formats: which composer view feeds the page (the `notes` module reads either).
pub const FORMAT_BSN1: u8 = 0; // get_score_notes: Beast canons, 7 bits per note
pub const FORMAT_BSI1: u8 = 1; // get_score_instructions: any music, 62-bit instructions

#[starknet::interface]
pub trait IBeastSoundNotesPageInfo<T> {
    fn composer(self: @T) -> starknet::ContractAddress;
    fn format(self: @T) -> u8;
}

/// The notes page: the chain composes. token_uri asks the Cairo composer for the score's BSN1 felts
/// and writes them into the page, which only decodes and plays them (deploy it with the notes
/// module list: midi, synth, play, notes, page). Same interface as BeastSoundPage, so the NFT can
/// point at either.
#[starknet::contract]
pub mod BeastSoundNotesPage {
    use starknet::ContractAddress;
    use starknet::storage::{
        MutableVecTrait, StoragePointerReadAccess, StoragePointerWriteAccess, Vec, VecTrait,
    };
    use super::{
        BeastSoundInputs, IBeastSoundComposerDispatcher, IBeastSoundComposerDispatcherTrait,
        IBeastSoundModuleDispatcher, IBeastSoundModuleDispatcherTrait,
    };

    #[storage]
    struct Storage {
        modules: Vec<ContractAddress>,
        composer: ContractAddress,
        format: u8,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, modules: Array<ContractAddress>, composer: ContractAddress, format: u8,
    ) {
        assert(modules.len() > 0, 'no modules');
        assert(format == super::FORMAT_BSN1 || format == super::FORMAT_BSI1, 'bad format');
        for m in modules {
            self.modules.push(m);
        }
        self.composer.write(composer);
        self.format.write(format);
    }

    #[abi(embed_v0)]
    impl BeastSoundPageImpl of super::IBeastSoundPage<ContractState> {
        fn token_uri(
            self: @ContractState,
            members: ByteArray,
            svg_b64: ByteArray,
            token_id: u256,
            live: BeastSoundInputs,
        ) -> ByteArray {
            let composer = IBeastSoundComposerDispatcher { contract_address: self.composer.read() };
            let felts = if self.format.read() == super::FORMAT_BSI1 {
                composer.get_score_instructions(token_id, live)
            } else {
                composer.get_score_notes(token_id, live)
            };
            let mut stored = super::page_data::head_segment();
            for i in 0..self.modules.len() {
                let module = IBeastSoundModuleDispatcher { contract_address: self.modules.at(i).read() };
                stored.append(@module.segment());
            }
            super::token_uri_with_line(@members, @svg_b64, @super::notes_html(felts.span()), @stored)
        }

        fn modules(self: @ContractState) -> Array<ContractAddress> {
            let mut out = array![];
            for i in 0..self.modules.len() {
                out.append(self.modules.at(i).read());
            }
            out
        }
    }

    #[abi(embed_v0)]
    impl InfoImpl of super::IBeastSoundNotesPageInfo<ContractState> {
        fn composer(self: @ContractState) -> ContractAddress {
            self.composer.read()
        }

        fn format(self: @ContractState) -> u8 {
            self.format.read()
        }
    }
}

/// Test stand-in for BeastSoundComposer: returns fixed felts (the real composer's output is checked
/// against the JS engine by the package's golden tests).
#[cfg(test)]
#[starknet::contract]
pub mod MockComposer {
    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl ComposerImpl of super::IBeastSoundComposer<ContractState> {
        fn get_score_notes(
            self: @ContractState, token_id: u256, live: super::BeastSoundInputs,
        ) -> Array<felt252> {
            crate::tests::warlock_felts()
        }

        fn get_score_instructions(
            self: @ContractState, token_id: u256, live: super::BeastSoundInputs,
        ) -> Array<felt252> {
            crate::tests::warlock_bsi_felts()
        }
    }
}

#[cfg(test)]
mod tests;
