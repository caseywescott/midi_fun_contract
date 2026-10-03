use core::array::{ArrayTrait, SpanTrait};
use core::option::OptionTrait;
use core::traits::TryInto;

#[derive(Drop)]
struct MidiOutput {
    data: Array<u8>,
}

trait MidiOutputTrait {
    fn new() -> MidiOutput;
    fn append_byte(ref self: MidiOutput, value: u8);
    fn append_bytes(ref self: MidiOutput, values: Array<u8>);
    fn len(self: @MidiOutput) -> usize;
    fn get_data(self: @MidiOutput) -> Array<u8>;
}

impl MidiOutputImpl of MidiOutputTrait {
    fn new() -> MidiOutput {
        MidiOutput { data: ArrayTrait::new() }
    }

    fn append_byte(ref self: MidiOutput, value: u8) {
        self.data.append(value);
    }

    fn append_bytes(ref self: MidiOutput, mut values: Array<u8>) {
        loop {
            match values.pop_front() {
                Option::Some(value) => { self.data.append(value); },
                Option::None => { break; },
            };
        }
    }

    fn len(self: @MidiOutput) -> usize {
        self.data.len()
    }

    fn get_data(self: @MidiOutput) -> Array<u8> {
        let mut result = ArrayTrait::new();
        let mut data = self.data.span();
        loop {
            match data.pop_front() {
                Option::Some(value) => { result.append(*value); },
                Option::None => { break; },
            };
        }
        result
    }
}

/// Pack raw MIDI bytes for RPC transport (Koji PRD v0.2 §5.2).
/// Element `[0]` is `midi_bytes.len()`; each subsequent felt packs up to 31 bytes big-endian.
/// Must match `frontend/lib/packMidiToFelts.ts` and `deserializeFeltsToMidi`.
pub fn to_felt252_array(mut midi_bytes: Array<u8>) -> Array<felt252> {
    let mut result: Array<felt252> = ArrayTrait::new();
    let total_len = midi_bytes.len();
    result.append(total_len.into());

    let mut i: usize = 0;
    loop {
        if i >= total_len {
            break;
        }
        let mut val: u256 = 0;
        let mut j: usize = 0;
        loop {
            if j >= 31 {
                break;
            }
            if i + j >= total_len {
                break;
            }
            val = val * 256_u256 + (*midi_bytes.at(i + j)).into();
            j += 1;
        }
        result.append(val.try_into().unwrap());
        i += 31;
    }
    result
}
