//! Boundary probes. `KernelProbe` builds `n` bytes of track bodies (4 tracks) inside the call and
//! then: returns their length (`build`), library-calls `Sink.take` with them (`take`: the cost of
//! serializing them into calldata and the callee's deserialization), library-calls `Sink.noop`
//! (`noop`: the bare call), assembles the file locally (`smf_local`) or through the kernel
//! (`smf_kernel`). Differences of these calls are the boundary's cost per byte.
use starknet::ClassHash;

#[starknet::interface]
pub trait ISink<T> {
    fn noop(self: @T);
    fn take(self: @T, tracks: Span<Array<u8>>) -> u32;
    fn take_felts(self: @T, words: Span<felt252>) -> u32;
}

#[starknet::contract]
pub mod Sink {
    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl SinkImpl of super::ISink<ContractState> {
        fn noop(self: @ContractState) {}
        fn take(self: @ContractState, tracks: Span<Array<u8>>) -> u32 {
            tracks.len()
        }
        fn take_felts(self: @ContractState, words: Span<felt252>) -> u32 {
            words.len()
        }
    }
}

#[starknet::interface]
pub trait IKernelProbe<T> {
    fn build(self: @T, n: u32) -> u32;
    fn noop(self: @T, sink: ClassHash) -> u32;
    fn take(self: @T, sink: ClassHash, n: u32) -> u32;
    fn smf_local(self: @T, n: u32) -> ByteArray;
    fn smf_kernel(self: @T, kernel: ClassHash, n: u32) -> ByteArray;
    fn build_felts(self: @T, n: u32) -> u32;
    fn take_felts(self: @T, sink: ClassHash, n: u32) -> u32;
}

/// `n` felts (no range check on the callee's side: the cost of a packed, one-felt-per-event or
/// 31-bytes-per-felt boundary).
pub fn felts_of(n: u32) -> Array<felt252> {
    let mut out: Array<felt252> = array![];
    let mut i: u32 = 0;
    while i < n {
        out.append((i * 7919).into());
        i += 1;
    }
    out
}

/// Four track bodies of `n` bytes in all (pseudo-random bytes below 0x80).
pub fn tracks_of(n: u32) -> Array<Array<u8>> {
    let mut out: Array<Array<u8>> = array![];
    let mut t: u32 = 0;
    let mut x: u64 = 12345;
    while t < 4 {
        let mut body: Array<u8> = array![];
        let mut i: u32 = 0;
        let len = if t == 3 {
            n - 3 * (n / 4)
        } else {
            n / 4
        };
        while i < len {
            x = (x * 1103515245 + 12345) % 0x80000000;
            body.append((x % 128).try_into().unwrap());
            i += 1;
        }
        out.append(body);
        t += 1;
    }
    out
}

#[starknet::contract]
pub mod KernelProbe {
    use midi::kernel::{IMidiKernelDispatcherTrait, IMidiKernelLibraryDispatcher};
    use starknet::ClassHash;
    use super::{ISinkDispatcherTrait, ISinkLibraryDispatcher, felts_of, tracks_of};

    #[storage]
    struct Storage {}

    #[abi(embed_v0)]
    impl KernelProbeImpl of super::IKernelProbe<ContractState> {
        fn build(self: @ContractState, n: u32) -> u32 {
            tracks_of(n).len()
        }
        fn noop(self: @ContractState, sink: ClassHash) -> u32 {
            ISinkLibraryDispatcher { class_hash: sink }.noop();
            0
        }
        fn take(self: @ContractState, sink: ClassHash, n: u32) -> u32 {
            ISinkLibraryDispatcher { class_hash: sink }.take(tracks_of(n).span())
        }
        fn smf_local(self: @ContractState, n: u32) -> ByteArray {
            midi::smf::smf_byte_array(1, 480, tracks_of(n).span())
        }
        fn smf_kernel(self: @ContractState, kernel: ClassHash, n: u32) -> ByteArray {
            IMidiKernelLibraryDispatcher { class_hash: kernel }
                .smf_byte_array(1, 480, tracks_of(n).span())
        }
        fn build_felts(self: @ContractState, n: u32) -> u32 {
            felts_of(n).len()
        }
        fn take_felts(self: @ContractState, sink: ClassHash, n: u32) -> u32 {
            ISinkLibraryDispatcher { class_hash: sink }.take_felts(felts_of(n).span())
        }
    }
}
