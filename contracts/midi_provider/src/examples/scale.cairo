//! ScaleMidiProvider: a short pentatonic loop for any token of one configured collection.
//!
//! Everything comes from `poseidon(token_address, token_id)`: tempo, key and the melody. Unlike
//! the Beast scores it chooses its own instruments (General MIDI marimba and fingered bass) and
//! plays its own hi-hat on the percussion channel, so the sound page plays it exactly as written.
//! Its General MIDI programs need no custom sounds, so `get_sound` pairs the MIDI with the class's
//! `default_settings()`.

#[starknet::contract]
pub mod ScaleMidiProvider {
    use core::poseidon::poseidon_hash_span;
    use midi::smf::{TrackWriterTrait, smf_bytes};
    use starknet::ContractAddress;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use crate::synth::{ISoundProvider, TokenSound, default_settings};
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
        fn get_midi(self: @ContractState, token_id: u256) -> ByteArray {
            compose(self.collection.read(), token_id)
        }

        fn get_midi_for(
            self: @ContractState, token_address: ContractAddress, token_id: u256,
        ) -> ByteArray {
            assert(token_address == self.collection.read(), 'unsupported collection');
            compose(token_address, token_id)
        }
    }

    #[abi(embed_v0)]
    impl SoundProviderImpl of ISoundProvider<ContractState> {
        fn get_sound(self: @ContractState, token_id: u256) -> TokenSound {
            TokenSound {
                midi: compose(self.collection.read(), token_id), settings: default_settings(),
            }
        }
    }

    fn compose(token_address: ContractAddress, token_id: u256) -> ByteArray {
        let seed: u256 = poseidon_hash_span(
            array![token_address.into(), token_id.low.into(), token_id.high.into()].span(),
        )
            .into();
        bytes_to_byte_array(scale_smf(seed).span())
    }

    fn pentatonic(degree: u32) -> u32 {
        let steps = array![0_u32, 2, 4, 7, 9].span();
        (degree / 5) * 12 + *steps.at(degree % 5)
    }

    /// Format 0, one track: tempo, two program changes, then melody, bass and hi-hat.
    pub fn scale_smf(seed: u256) -> Array<u8> {
        let bpm: u32 = 96 + (seed % 48).try_into().unwrap();
        let tempo_us: u32 = 60000000 / bpm;
        let tonic: u32 = 48 + ((seed / 48) % 12).try_into().unwrap();
        let mut walk: u256 = seed / 576;

        let mut track = TrackWriterTrait::new();
        track.tempo(0, tempo_us);
        track.program(0, 0, MARIMBA);
        track.program(0, 1, FINGERED_BASS);

        let mut degree: u32 = 5;
        let mut bass: u8 = 0;
        let mut step: u32 = 0;
        while step < STEPS {
            let t = step * STEP;
            if step % 4 == 0 {
                if step > 0 {
                    track.note_off(t, 1, bass, 64);
                }
                let root = if step % 8 == 0 {
                    tonic - 12
                } else {
                    tonic - 5
                };
                bass = root.try_into().unwrap();
                track.note_on(t, 1, bass, 90);
            }
            if step % 2 == 0 {
                track.note_on(t, 9, CLOSED_HAT, 70);
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
            track.note_on(t, 0, note, 100);
            track.note_off(t + STEP - 40, 0, note, 64);
            step += 1;
        }
        track.note_off(STEPS * STEP, 1, bass, 64);
        smf_bytes(0, PPQN.try_into().unwrap(), array![track.finish()].span())
    }
}
