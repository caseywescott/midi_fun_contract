// Local end-to-end check (not part of the patch): real art providers + the real BeastSoundPage.
use beasts_nft::interfaces::{IBeastsDispatcher, IBeastsDispatcherTrait};
use openzeppelin_interfaces::erc721::{IERC721MetadataDispatcher, IERC721MetadataDispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, declare, start_cheat_caller_address,
    stop_cheat_caller_address,
};
use starknet::ContractAddress;

fn addr(a: felt252) -> ContractAddress {
    a.try_into().unwrap()
}

fn deploy_no_args(name: ByteArray) -> ContractAddress {
    let (a, _) = declare(name).unwrap().contract_class().deploy(@array![]).unwrap();
    a
}

fn setup() -> (IBeastsDispatcher, IERC721MetadataDispatcher, ContractAddress, u256, u256) {
    let png = deploy_no_args("beast_png_regular_data");
    let png_shiny = deploy_no_args("beast_png_shiny_data");
    let gif = deploy_no_args("beast_gif_regular_data");
    let gif_shiny = deploy_no_args("beast_gif_shiny_data");
    let owner = addr('owner');
    let mut calldata: Array<felt252> = array![0, 'Beasts', 6, 0, 'BEAST', 5];
    calldata.append(owner.into());
    calldata.append(addr('royalty').into());
    calldata.append(500);
    calldata.append(png.into());
    calldata.append(png_shiny.into());
    calldata.append(gif.into());
    calldata.append(gif_shiny.into());
    calldata.append(0);
    let (nft, _) = declare("beasts_nft").unwrap().contract_class().deploy(@calldata).unwrap();
    let beasts = IBeastsDispatcher { contract_address: nft };
    start_cheat_caller_address(nft, owner);
    beasts.set_dungeon_address(addr('minter'));
    stop_cheat_caller_address(nft);
    start_cheat_caller_address(nft, addr('minter'));
    // Sorrow Peak Warlock-like (tier 1) and an animated shiny one
    let (plain, _, _) = beasts.mint(addr('holder'), 1, 33, 10, 126, 229, 0, 0);
    let (fancy, _, _) = beasts.mint(addr('holder'), 1, 34, 11, 50, 120, 1, 1);
    stop_cheat_caller_address(nft);
    (beasts, IERC721MetadataDispatcher { contract_address: nft }, owner, plain, fancy)
}

fn enable_sound(beasts: IBeastsDispatcher, owner: ContractAddress) {
    let mut modules: Array<felt252> = array![9];
    for name in array![
        "BeastSoundModuleCore", "BeastSoundModuleBeast", "BeastSoundModuleMusic", "BeastSoundModuleMidi",
        "BeastSoundModuleSynth", "BeastSoundModulePlay", "BeastSoundModuleFx", "BeastSoundModuleApi",
        "BeastSoundModulePage",
    ] {
        modules.append(deploy_no_args(name).into());
    }
    let (page, _) = declare("BeastSoundPage").unwrap().contract_class().deploy(@modules).unwrap();
    start_cheat_caller_address(beasts.contract_address, owner);
    beasts.set_sound_page_address(page);
    stop_cheat_caller_address(beasts.contract_address);
    assert!(beasts.get_sound_page_address() == page);
}

#[test]
fn e2e_without_sound() {
    let (_, metadata, _, plain, fancy) = setup();
    println!("URI_PLAIN_OFF {}", metadata.token_uri(plain));
    println!("URI_FANCY_OFF {}", metadata.token_uri(fancy));
}

#[test]
fn e2e_with_sound() {
    let (beasts, metadata, owner, plain, fancy) = setup();
    enable_sound(beasts, owner);
    println!("URI_PLAIN_ON {}", metadata.token_uri(plain));
    println!("URI_FANCY_ON {}", metadata.token_uri(fancy));
}

#[test]
fn e2e_gas_setup_only() {
    let (beasts, _, owner, _, _) = setup();
    enable_sound(beasts, owner);
}

#[test]
fn e2e_gas_plain_off() {
    let (_, metadata, _, plain, _) = setup();
    let _ = metadata.token_uri(plain);
}

#[test]
fn e2e_gas_plain_on() {
    let (beasts, metadata, owner, plain, _) = setup();
    enable_sound(beasts, owner);
    let _ = metadata.token_uri(plain);
}
