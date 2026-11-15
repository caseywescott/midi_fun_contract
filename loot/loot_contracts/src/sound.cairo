//! `LootSound`: the Loot Dungeon Sound front contract. Stateless apart from the class hashes it
//! library-calls (set once at deploy) and the FM sound pack's address.
#[starknet::contract]
pub mod LootSound {
    use beast_composer::composition::drift::DriftClock;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress};
    use crate::interfaces::{
        ILootSongComposerDispatcherTrait, ILootSongComposerLibraryDispatcher, ILootSound,
        ILootTrackComposerDispatcherTrait, ILootTrackComposerLibraryDispatcher,
    };

    #[storage]
    struct Storage {
        song_class: ClassHash,
        edition_class: ClassHash,
        round_class: ClassHash,
        pack: ContractAddress,
    }

    /// `edition_class` serves `edition`; `round_class` serves `round` and `sound_check` (the same
    /// class hash for both when one class holds all three).
    #[constructor]
    fn constructor(
        ref self: ContractState,
        song_class: ClassHash,
        edition_class: ClassHash,
        round_class: ClassHash,
        pack: ContractAddress,
    ) {
        self.song_class.write(song_class);
        self.edition_class.write(edition_class);
        self.round_class.write(round_class);
        self.pack.write(pack);
    }

    #[abi(embed_v0)]
    impl SoundImpl of ILootSound<ContractState> {
        fn species_song(
            self: @ContractState, species: u32, mega: bool, drift: Option<DriftClock>,
        ) -> ByteArray {
            ILootSongComposerLibraryDispatcher { class_hash: self.song_class.read() }
                .song(species, mega, 0, drift)
        }

        fn name_song(
            self: @ContractState, species: u32, mega: bool, name: u16, drift: Option<DriftClock>,
        ) -> ByteArray {
            assert(name >= 1 && name <= 1242, 'name variant 1..1242');
            ILootSongComposerLibraryDispatcher { class_hash: self.song_class.read() }
                .song(species, mega, name, drift)
        }

        fn edition(
            self: @ContractState,
            species: u32,
            mega: bool,
            edition: u32,
            purchase: u64,
            drift: Option<DriftClock>,
        ) -> ByteArray {
            ILootTrackComposerLibraryDispatcher { class_hash: self.edition_class.read() }
                .edition(species, mega, edition, purchase, drift)
        }

        fn round(
            self: @ContractState, species: u32, mega: bool, purchase: u64, drift: Option<DriftClock>,
        ) -> ByteArray {
            ILootTrackComposerLibraryDispatcher { class_hash: self.round_class.read() }
                .round(species, mega, purchase, drift)
        }

        fn sound_check(self: @ContractState, species: u32, mega: bool, take: u64) -> ByteArray {
            ILootTrackComposerLibraryDispatcher { class_hash: self.round_class.read() }
                .sound_check(species, mega, take)
        }

        fn sound_pack(self: @ContractState) -> ContractAddress {
            self.pack.read()
        }
    }
}
