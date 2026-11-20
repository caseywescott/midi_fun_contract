//! EXPERIMENT (exp/kernel-libcall): `MidiKernel`, the shared helpers of every composer in one class,
//! declared once and reached by library call (`midi::kernel::IMidiKernelLibraryDispatcher`).
//! Storage-free and syscall-free, so it behaves the same in any caller's context.

#[starknet::contract]
pub mod MidiKernel {
    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl MidiKernelImpl of midi::kernel::IMidiKernel<ContractState> {
        fn smf_byte_array(
            self: @ContractState, format: u16, division: u16, tracks: Span<Array<u8>>,
        ) -> ByteArray {
            midi::smf::smf_byte_array(format, division, tracks)
        }
    }
}
