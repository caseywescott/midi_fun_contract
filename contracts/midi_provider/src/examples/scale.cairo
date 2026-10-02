//! ScaleMidiProvider: a short pentatonic loop for any token of one configured collection.
//!
//! Everything comes from `poseidon(token_address, token_id)`: tempo, key and the melody. Unlike
//! the Beast scores it chooses its own instruments (General MIDI marimba and fingered bass) and
//! plays its own hi-hat on the percussion channel, so the sound page plays it exactly as written.

#[starknet::contract]
pub mod ScaleMidiProvider {
    use core::poseidon::poseidon_hash_span;
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::{IMidiProvider, bytes_to_byte_array};

    const PPQN: u32 = 480;
    const STEP: u32 = 240; // eighth notes
    const STEPS: u32 = 16; // two 4/4 bars
    const MARIMBA: u8 = 12;
    const FINGERED_BASS: u8 = 33;
    const CLOSED_HAT: u8 = 42;

    #[storage]
    struct Storage {
        collection: ContractAddress,
    }

    #[constructor]
    fn constructor(ref self: ContractState, collection: ContractAddress) {
        self.collection.write(collection);
    }

    #[abi(embed_v0)]
    impl ScaleMidiProviderImpl of IMidiProvider<ContractState> {
        fn get_midi(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> ByteArray {
            assert(token_address == self.collection.read(), 'unsupported collection');
            let seed: u256 = poseidon_hash_span(
                array![token_address.into(), token_id.low.into(), token_id.high.into()].span(),
            )
                .into();
            bytes_to_byte_array(scale_smf(seed).span())
        }
    }

    fn pentatonic(degree: u32) -> u32 {
        let steps = array![0_u32, 2, 4, 7, 9].span();
        (degree / 5) * 12 + *steps.at(degree % 5)
    }

    #[derive(Drop)]
    struct Track {
        bytes: Array<u8>,
        last: u32,
    }

    fn push_vlq(ref out: Array<u8>, v: u32) {
        if v >= 0x4000 {
            out.append((0x80 + (v / 0x4000) % 128).try_into().unwrap());
        }
        if v >= 0x80 {
            out.append((0x80 + (v / 0x80) % 128).try_into().unwrap());
        }
        out.append((v % 128).try_into().unwrap());
    }

    fn event(ref track: Track, time: u32, status: u8, data1: u8, data2: u8) {
        push_vlq(ref track.bytes, time - track.last);
        track.last = time;
        track.bytes.append(status);
        track.bytes.append(data1);
        track.bytes.append(data2);
    }

    fn push_u32_be(ref out: Array<u8>, v: u32) {
        out.append(((v / 0x1000000) % 256).try_into().unwrap());
        out.append(((v / 0x10000) % 256).try_into().unwrap());
        out.append(((v / 0x100) % 256).try_into().unwrap());
        out.append((v % 256).try_into().unwrap());
    }

    /// Format 0, one track: tempo, two program changes, then melody, bass and hi-hat.
    pub fn scale_smf(seed: u256) -> Array<u8> {
        let bpm: u32 = 96 + (seed % 48).try_into().unwrap();
        let tempo_us: u32 = 60000000 / bpm;
        let tonic: u32 = 48 + ((seed / 48) % 12).try_into().unwrap();
        let mut walk: u256 = seed / 576;

        let mut track = Track { bytes: array![], last: 0 };
        track.bytes.append_span(array![0, 0xFF, 0x51, 0x03].span());
        track.bytes.append(((tempo_us / 0x10000) % 256).try_into().unwrap());
        track.bytes.append(((tempo_us / 0x100) % 256).try_into().unwrap());
        track.bytes.append((tempo_us % 256).try_into().unwrap());
        track.bytes.append_span(array![0, 0xC0, MARIMBA, 0, 0xC1, FINGERED_BASS].span());

        let mut degree: u32 = 5;
        let mut bass: u8 = 0;
        let mut step: u32 = 0;
        while step < STEPS {
            let t = step * STEP;
            if step % 4 == 0 {
                if step > 0 {
                    event(ref track, t, 0x81, bass, 64);
                }
                let root = if step % 8 == 0 {
                    tonic - 12
                } else {
                    tonic - 5
                };
                bass = root.try_into().unwrap();
                event(ref track, t, 0x91, bass, 90);
            }
            if step % 2 == 0 {
                event(ref track, t, 0x99, CLOSED_HAT, 70);
            }
            // A random walk over the scale, kept inside two octaves.
            let move_: u32 = (walk % 5).try_into().unwrap();
            walk = walk / 5;
            degree =
                if move_ < 2 && degree > 1 {
                    degree - 1 - move_
                } else if move_ >= 3 && degree < 9 {
                    degree + move_ - 2
                } else {
                    degree
                };
            let note: u8 = (tonic + 12 + pentatonic(degree)).try_into().unwrap();
            event(ref track, t, 0x90, note, 100);
            event(ref track, t + STEP - 40, 0x80, note, 64);
            step += 1;
        }
        event(ref track, STEPS * STEP, 0x81, bass, 64);
        track.bytes.append_span(array![0, 0xFF, 0x2F, 0].span());

        let mut out: Array<u8> = array![];
        push_u32_be(ref out, 0x4D546864); // MThd
        push_u32_be(ref out, 6);
        out.append_span(array![0, 0, 0, 1, (PPQN / 256).try_into().unwrap(), 0xE0].span());
        push_u32_be(ref out, 0x4D54726B); // MTrk
        push_u32_be(ref out, track.bytes.len());
        out.append_span(track.bytes.span());
        out
    }
}
