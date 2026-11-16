//! `LootMidiProvider`: every Loot Dungeon Sound track behind one ABI (`ILootMidiProvider`), in the
//! pattern of Beast Sound v1.1.0: a storage-free composer class does the composing, this contract
//! knows where the classes live.
//!
//! - Editions, Rounds and Sound Checks: library calls into `LootPureComposer` (band, lift and an
//!   edition style's MIX written in place).
//! - Species and Name Songs: the Loot Beast's song inputs (`genesis::genesis_song_inputs`, level 1,
//!   health 100, as the Loot lab calls the Beasts composer) played by the pinned v1.1.0
//!   `BeastPureComposer` (a library call: the same class every Beast plays), then given the lab's band
//!   (a Species Song's drifts with the day, a Name Song's does not) and a Name Song lifted an octave.
//! - Songs: the band (a Name Song's lead from NAME_LEADS, both kinds drifting with the species) and
//!   the volumes (loot-lab.mjs `track0()`: LEAD_SOFT x LEAD_ALL and LEAD_DROP on the theme, NAME_SOFT).
//! - Every kind: the lab's TOP_SOFT (loot-lab.mjs `track()`, a sample bank such as the FM bank): the
//!   highest voice's volume turned down when its instrument is one of TOP_SOFT. Done here, on the
//!   finished file, when the band has such an instrument (the composer class has no room for it).
//!
//! Upgrades (OpenZeppelin Ownable and Upgradeable, as v1.1's `BeastMidiProvider`): the owner (set at
//! deploy) can `upgrade` the class or `set_classes`; `renounce_ownership` ends both for good.

/// A Loot Beast as the Beasts composer sees it in the lab (`sampleTrackMidi`: level 1, health 100).
pub fn loot_beast(
    species: u32, prefix: u8, suffix: u8,
) -> beast_composer::composition::beast_v3_sound::PackableBeastV3 {
    let s = loot_composer::species::loot_species(species);
    beast_composer::composition::beast_v3_sound::PackableBeastV3 {
        id: species.into(),
        prefix,
        suffix,
        level: 1,
        health: 100,
        shiny: 0,
        animated: 0,
        tier: s.tier,
        beast_type: s.beast_type,
    }
}

#[starknet::contract]
pub mod LootMidiProvider {
    use beast_composer::composition::genesis::genesis_song_inputs;
    use beast_composer::inputs::ComposerInputs;
    use beast_composer::inputs::drift::DriftInputs;
    use loot_composer::orchestra::{
        band, byte_array_bytes, has_soft, orchestrate, orchestrate_byte_array, round_band, song_band,
        song_vols, top_soft_byte_array, top_soft_smf,
    };
    use loot_composer::orchestra_data::{NAME_KICK_SOFT, STYLE_COUNT};
    use loot_composer::songs::name_from_variant;
    use loot_composer::species::loot_species;
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_interfaces::upgrades::IUpgradeable;
    use openzeppelin_upgrades::UpgradeableComponent;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::{ClassHash, ContractAddress};
    use crate::composer::{loot_drift, mega_of};
    use crate::interfaces::{
        IBeastPureComposerDispatcherTrait, IBeastPureComposerLibraryDispatcher, ILootMidiProvider,
        ILootPureComposerDispatcherTrait, ILootPureComposerLibraryDispatcher, LootInputs,
        LootSongInputs,
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    /// OpenZeppelin Ownable: `owner`, `transfer_ownership`, `renounce_ownership`.
    #[abi(embed_v0)]
    impl OwnableImpl = OwnableComponent::OwnableImpl<ContractState>;
    impl OwnableInternalImpl = OwnableComponent::InternalImpl<ContractState>;
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        composer_class: ClassHash,
        song_class: ClassHash,
        pack: ContractAddress,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
    }

    /// `composer_class`: `LootPureComposer`; `song_class`: Beast Sound v1.1.0 `BeastPureComposer`
    /// (0x07eb6480204a1367381b782116e6a3d6dedd8fb8b03535ca453e5c681002eb63); `pack`: `LootFmPack`.
    #[constructor]
    fn constructor(
        ref self: ContractState,
        composer_class: ClassHash,
        song_class: ClassHash,
        pack: ContractAddress,
        owner: ContractAddress,
    ) {
        self.composer_class.write(composer_class);
        self.song_class.write(song_class);
        self.pack.write(pack);
        self.ownable.initializer(owner);
    }

    #[abi(embed_v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.upgradeable.upgrade(new_class_hash);
        }
    }

    /// A Species or Name Song: the pinned Beast composer's file, with the lab's band and lift.
    fn song(
        self: @ContractState, x: LootSongInputs, sound_effects: u8, drift: Option<DriftInputs>,
    ) -> ByteArray {
        assert(x.name <= 1242, 'invalid music name');
        mega_of(sound_effects);
        let (prefix, suffix) = name_from_variant(x.name);
        let beast = super::loot_beast(x.species, prefix, suffix);
        let inputs = ComposerInputs::Song(genesis_song_inputs(beast, prefix, suffix, 0, Option::None));
        let beasts = IBeastPureComposerLibraryDispatcher { class_hash: self.song_class.read() };
        // day 1 is as written (the lab); a song's drift is its name's
        let day = match drift {
            Option::Some(d) => if d.day >= 2 {
                Option::Some(DriftInputs { name_variant_id: x.name, ..d })
            } else {
                Option::None
            },
            Option::None => Option::None,
        };
        let sound = match day {
            Option::Some(d) => beasts.compose_drift(inputs, sound_effects, d),
            Option::None => beasts.compose(inputs, sound_effects),
        };
        // the band drifts with the species' clock, a Name Song's as a Species Song's (the lab, cc0c9d4);
        // a Name Song's lead comes from NAME_LEADS by species and name
        let band = song_band(
            loot_species(x.species).beast_type, x.species, x.name.into(), loot_drift(x.species, day),
        );
        let lift = if x.name == 0 {
            0
        } else {
            12
        };
        // the volumes (LEAD_SOFT x LEAD_ALL and LEAD_DROP on the theme, NAME_SOFT on a Name Song) in
        // the same pass as the band and lift, then TOP_SOFT on the highest voice when the band has
        // such an instrument (the lab's track0() and track())
        let vol = song_vols(band.span(), x.name != 0);
        // a Name Song's kick (keys 35, 36) NAME_KICK_SOFT velocity steps softer (the lab's drumSoft)
        let kick = if x.name == 0 {
            0
        } else {
            NAME_KICK_SOFT
        };
        if has_soft(band.span()) {
            let smf = orchestrate(
                byte_array_bytes(@sound.midi).span(), band.span(), lift, vol.span(), kick,
            );
            top_soft_byte_array(smf.span(), band.span())
        } else {
            orchestrate_byte_array(
                byte_array_bytes(@sound.midi).span(), band.span(), lift, vol.span(), kick,
            )
        }
    }

    fn route(
        self: @ContractState, inputs: LootInputs, sound_effects: u8, drift: Option<DriftInputs>,
    ) -> ByteArray {
        match inputs {
            LootInputs::Song(x) => song(self, x, sound_effects, drift),
            _ => {
                let c = ILootPureComposerLibraryDispatcher { class_hash: self.composer_class.read() };
                let out = match drift {
                    Option::Some(d) => c.compose_drift(inputs, sound_effects, d),
                    Option::None => c.compose(inputs, sound_effects),
                };
                // TOP_SOFT (the lab's track(), sample banks): only a band with such an instrument
                // can need it; the instrument is then read from the file (the band, written in
                // place: an edition's accompaniment may have been changed to the low instrument)
                let band = match inputs {
                    LootInputs::Edition(x) => band(
                        (x.edition - 1) % STYLE_COUNT,
                        x.species,
                        x.edition,
                        x.purchase.try_into().unwrap(),
                        loot_drift(x.species, drift),
                    ),
                    LootInputs::Round(x) => round_band(
                        loot_species(x.species).beast_type, x.species, loot_drift(x.species, drift),
                    ),
                    LootInputs::SoundCheck(x) => round_band(
                        loot_species(x.species).beast_type, x.species, Option::None,
                    ),
                    LootInputs::Song(_) => array![],
                };
                if !has_soft(band.span()) {
                    return out;
                }
                match top_soft_smf(byte_array_bytes(@out).span(), array![].span()) {
                    Option::Some(x) => midi::pack::bytes_to_byte_array(x.span()),
                    Option::None => out,
                }
            },
        }
    }

    #[abi(embed_v0)]
    impl ProviderImpl of ILootMidiProvider<ContractState> {
        fn compose(self: @ContractState, inputs: LootInputs, sound_effects: u8) -> ByteArray {
            route(self, inputs, sound_effects, Option::None)
        }

        fn compose_drift(
            self: @ContractState, inputs: LootInputs, sound_effects: u8, drift: DriftInputs,
        ) -> ByteArray {
            route(self, inputs, sound_effects, Option::Some(drift))
        }

        fn sound_pack(self: @ContractState) -> ContractAddress {
            self.pack.read()
        }

        fn get_composer_class(self: @ContractState) -> ClassHash {
            self.composer_class.read()
        }

        fn get_song_class(self: @ContractState) -> ClassHash {
            self.song_class.read()
        }

        fn set_classes(
            ref self: ContractState,
            composer_class: ClassHash,
            song_class: ClassHash,
            pack: ContractAddress,
        ) {
            self.ownable.assert_only_owner();
            self.composer_class.write(composer_class);
            self.song_class.write(song_class);
            self.pack.write(pack);
        }
    }
}
