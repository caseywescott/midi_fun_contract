//! EXPERIMENT (exp/kernel-libcall): the interface of a shared "MIDI kernel" class that composers
//! reach by library call instead of each carrying their own copy of the helpers. The class itself
//! is `midi_contracts::kernel::MidiKernel`. Boundary: whole-file assembly (track bodies in, the
//! finished Standard MIDI File out as a `ByteArray`), one call per file. Per-event helpers
//! (`TrackWriter`) stay in the composer: a library call per note would cost far more than it saves.

#[starknet::interface]
pub trait IMidiKernel<T> {
    /// `midi::smf::smf_byte_array(format, division, tracks)`.
    fn smf_byte_array(
        self: @T, format: u16, division: u16, tracks: Span<Array<u8>>,
    ) -> ByteArray;
}
