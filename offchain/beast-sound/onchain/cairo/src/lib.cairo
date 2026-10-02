//! Beast Sound page: a Beast's `token_uri` with its theme as `animation_url`, built onchain.
//!
//! The Beasts NFT keeps building its JSON members and animated SVG exactly as today, then calls
//! `token_uri(members, svg_b64, token_id, live)` here instead of base64-encoding the JSON itself.
//! `animation_url` is an HTML page: the composer script (stored in this contract's code), one line
//! of per-token inputs, and the same SVG. The browser composes the theme from the inputs with
//! engine v1 and plays it on tap; nothing is fetched.
//!
//! Every piece is aligned to 3 bytes so base64 runs concatenate (see onchain/page.js):
//!
//!   "data:application/json;base64,"
//!     ++ b64('{' members ',' <spaces> '"image":"data:image/svg+xml;base64,')
//!     ++ b64(S) where S = svg_b64 '"' <spaces>          (encoded once, appended twice)
//!     ++ b64(',  ')
//!     ++ HEAD ++ MODULE_1 ++ … ++ MODULE_n               (encoded at build time; see below)
//!     ++ b64(b64(inputs line + '<script type="text/plain" id="art">'))
//!     ++ b64(S)
//!     ++ b64('}')
//!
//! So the per-call base64 work is the same as today's plus about 150 bytes.

//!
//! The library is split into modules (core, beast, music, midi, synth, play, fx, api, page), each in
//! its own contract (`modules.cairo`) exposing its segment, base64(base64(<script>…</script>)).
//! `BeastSoundPage` keeps the page HEAD and a fixed list of module contracts, and splices
//! HEAD ++ every module segment into animation_url. Other projects can reuse any module contract.

pub mod modules;
pub mod page_data;

/// A stored library module: its name and its segment, base64(base64(<script>…</script>)) padded so
/// segments concatenate. Decode a segment twice to get the module's script.
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
    pad_spaces(ref s, 9, art_open.len());
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

/// The complete token_uri, given the stored segment (HEAD ++ module segments).
pub fn token_uri(
    members: @ByteArray,
    svg_b64: @ByteArray,
    token_id: u256,
    live: BeastSoundInputs,
    stored: @ByteArray,
) -> ByteArray {
    let image_key: ByteArray = "\"image\":\"data:image/svg+xml;base64,";
    let mut s = svg_b64.clone();
    s.append_byte('"');
    pad_spaces(ref s, 3, 0);
    let s_b64 = base64(@s);

    let mut a: ByteArray = "{";
    a.append(members);
    a.append_byte(',');
    pad_spaces(ref a, 3, image_key.len());
    // Extra JSON whitespace (3 spaces = 4 base64 characters) until the stored library starts on a
    // 31-byte word boundary of the output, where appending it is cheap (29 = the URI prefix).
    while (29 + (a.len() + image_key.len()) / 3 * 4 + s_b64.len() + 4) % 31 != 0 {
        a.append(@"   ");
    }
    a.append(@image_key);

    let mut out: ByteArray = "data:application/json;base64,";
    append_base64(ref out, @a);
    out.append(@s_b64);
    append_base64(ref out, @",  ");
    out.append(stored);
    append_base64(ref out, @base64(@inputs_html(token_id, live)));
    out.append(@s_b64);
    append_base64(ref out, @"}");
    out
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

#[cfg(test)]
mod tests;
