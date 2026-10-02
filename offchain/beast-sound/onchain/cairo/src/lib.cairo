//! Generic MIDI page: NFT presentation → provider raw SMF → embedded offline TinySynth.
//! Only dynamic MIDI and artwork are encoded at runtime. The fixed player is pre-encoded.
pub mod page_data;

fn pad_spaces(ref s: ByteArray, multiple: usize) {
    while s.len() % multiple != 0 {
        s.append_byte(' ');
    }
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


// Split at 9 whole 31-byte words (279 bytes): Base64(prefix) is both JSON-aligned and
// HTML-aligned. Share that first encoded artwork fragment instead of processing SVG twice.
fn split_art(svg_b64: @ByteArray) -> (ByteArray, ByteArray) {
    let mut serialized: Array<felt252> = array![];
    svg_b64.serialize(ref serialized);
    let mut words = serialized.span();
    let full: usize = (*words.pop_front().unwrap()).try_into().unwrap();
    let prefix_words = full / 9 * 9;
    let mut prefix: ByteArray = Default::default();
    let mut suffix: ByteArray = Default::default();
    let mut i: usize = 0;
    while i < full {
        let word = *words.pop_front().unwrap();
        if i < prefix_words {
            prefix.append_word(word, 31);
        } else {
            suffix.append_word(word, 31);
        }
        i += 1;
    }
    let pending = *words.pop_front().unwrap();
    let length: usize = (*words.pop_front().unwrap()).try_into().unwrap();
    suffix.append_word(pending, length);
    (prefix, suffix)
}

pub fn midi_open_html(midi: @ByteArray) -> ByteArray {
    let art_open: ByteArray = "<script type=\"text/plain\" id=\"art\">";
    let mut head = base64(midi);
    head.append(@"</script>");
    while (head.len() + art_open.len()) % 9 != 0 {
        head.append_byte(' ');
    }
    head.append(@art_open);
    head
}

/// Closed inert Base64 payloads: neither raw artwork nor arbitrary MIDI is executable HTML.
pub fn midi_html(midi: @ByteArray, svg_b64: @ByteArray) -> ByteArray {
    let mut tail = midi_open_html(midi);
    tail.append(svg_b64);
    tail.append(@"</script></body></html>");
    tail
}

/// `members` is trusted JSON without braces/image; `svg_b64` is canonical SVG Base64.
pub fn token_uri(members: @ByteArray, svg_b64: @ByteArray, midi: @ByteArray) -> ByteArray {
    let image_key: ByteArray = "\"image\":\"data:image/svg+xml;base64,";
    let mut prefix: ByteArray = "{";
    prefix.append(members);
    prefix.append_byte(',');
    while (prefix.len() + image_key.len()) % 3 != 0 {
        prefix.append_byte(' ');
    }
    prefix.append(@image_key);
    let (art_prefix, art_suffix) = split_art(svg_b64);
    let art_once = base64(@art_prefix);
    let mut image_tail = art_suffix.clone();
    image_tail.append(@"\",");
    pad_spaces(ref image_tail, 3);
    let mut html_tail = art_suffix;
    html_tail.append(@"</script></body></html>");
    let mut json_tail = base64(@html_tail);
    json_tail.append(@"\"}");

    let mut out: ByteArray = "data:application/json;base64,";
    append_base64(ref out, @prefix);
    out.append(@art_once);
    append_base64(ref out, @image_tail);
    out.append(@page_data::stored_segment());
    append_base64(ref out, @base64(@midi_open_html(midi)));
    append_base64(ref out, @art_once);
    append_base64(ref out, @json_tail);
    out
}

#[starknet::interface]
pub trait IMidiPage<T> {
    fn token_uri(
        self: @T,
        members: ByteArray,
        svg_b64: ByteArray,
        token_address: starknet::ContractAddress,
        token_id: u256,
    ) -> ByteArray;
}

#[starknet::contract]
pub mod MidiPage {
    use core::num::traits::Zero;
    use midi_interfaces::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    #[storage]
    struct Storage {
        provider: ContractAddress,
    }
    #[constructor]
    fn constructor(ref self: ContractState, provider: ContractAddress) {
        assert(provider.is_non_zero(), 'MIDI provider unavailable');
        self.provider.write(provider);
    }
    #[abi(embed_v0)]
    impl MidiPageImpl of super::IMidiPage<ContractState> {
        fn token_uri(
            self: @ContractState,
            members: ByteArray,
            svg_b64: ByteArray,
            token_address: ContractAddress,
            token_id: u256,
        ) -> ByteArray {
            let midi = IMidiProviderDispatcher { contract_address: self.provider.read() }
                .get_midi(token_address, token_id);
            super::token_uri(@members, @svg_b64, @midi)
        }
    }
}
#[cfg(test)]
mod tests;
