//! Collection-independent raw Standard MIDI File provider ABI.
use starknet::ContractAddress;

#[starknet::interface]
pub trait IMidiProvider<T> {
    /// `token_address` is the NFT collection. The provider obtains all musical inputs itself.
    fn get_midi(self: @T, token_address: ContractAddress, token_id: u256) -> ByteArray;
}
