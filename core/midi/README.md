# midi

The core MIDI system's library: its data types and interfaces, and Standard MIDI File writing. A
Scarb `[lib]` package with no contracts, no storage and no syscalls. It depends on `starknet` (to
declare interfaces) and `tinysynth_interface`, onchain-midi-player's types package (whose types it
re-exports), and on nothing in `beasts/`. The Beast composer (`beasts/beast_composer`) and the
contracts (`core/midi_contracts`, `beasts/beast_contracts`) build on it.

```toml
[dependencies]
midi.workspace = true   # in this workspace
# from another repository:
# midi = { git = "https://github.com/caseywescott/midi_fun_contract", rev = "<commit>" }
```

| Module | What it holds |
|---|---|
| `midi::types` | `TinySynthSettings`, `TinySynthSound`, `Timbre`, `Operator`, `Waveform`, `WaveDef`, `Filter`, `FilterKind`, `FIXED_POINT_SCALE`: onchain-midi-player's own types, re-exported, so they are the types its class takes |
| `midi::interfaces` | `IMidiProvider`, `ISynthSettingsProvider`, `IMidiSoundPage`, and onchain-midi-player's `ISoundProvider`, each with its dispatchers |
| `midi::settings` | `default_settings()` and `validate(@settings)` for `TinySynthSettings` |
| `midi::smf` | Standard MIDI File writing (below) |
| `midi::pack` | Bytes out of a contract (below) |

```cairo
use midi::interfaces::{IMidiProviderDispatcher, IMidiProviderDispatcherTrait};
use midi::types::TinySynthSettings;
```

The rules a provider follows are in `core/midi_contracts/README.md`.

## `midi::smf`

```cairo
use midi::smf::{TrackWriterTrait, smf_bytes};

let mut tempo = TrackWriterTrait::new();
tempo.tempo(0, 500000);                    // 120 BPM
let mut lead = TrackWriterTrait::new();
lead.program(0, 0, 80);                    // channel 1
lead.control(0, 0, 10, 32);                // pan left
lead.note_on(0, 0, 60, 100);
lead.note_off(480, 0, 60, 64);
let mut drums = TrackWriterTrait::with_running_status();
drums.note_on(0, 9, 36, 120);              // channel 10
drums.note_on(480, 9, 38, 100);            // status byte omitted
let file: Array<u8> = smf_bytes(
    1, 480, array![tempo.finish_at(1920), lead.finish(), drums.finish_at(1920)].span(),
);
```

| Item | What it does |
|---|---|
| `TrackWriter` | A track body from timed events: absolute ticks in, delta times out; times must not go backwards (`'midi: time goes backwards'`) |
| `new()` / `with_running_status()` | Every status byte written, or repeated channel statuses omitted (meta events clear running status) |
| `note_on`, `note_off`, `program`, `control` | Channel messages (0-based channels; 9 is GM percussion) |
| `message`, `message1` | Any channel message with two or one data bytes |
| `meta`, `tempo` | Meta events; Set Tempo in microseconds per quarter |
| `finish()` / `finish_at(time)` | Closes the track with End of Track at the last event, or at `time` if later: a player that loops to the latest End of Track (onchain-midi-player) loops there |
| `smf_bytes(format, division, tracks)` | `MThd` plus one `MTrk` per body |
| `push_vlq`, `push_chunk`, `push_u32_be` | The primitives, for writers of their own |

## `midi::pack`

| Function | Returns |
|---|---|
| `bytes_to_byte_array(Span<u8>) -> ByteArray` | What `IMidiProvider::get_midi` returns; 31 bytes per word with felt arithmetic, several times cheaper than `append_byte` |
| `to_felt252_array(Span<u8>) -> Array<felt252>` | `[byte_len, 31-byte big-endian words...]`, the transport of the composer's benchmark views |

## Tests

`scarb test`: the SMF specification's variable-length quantity examples, deltas and End of Track,
running status, header and chunks, both packers at every length to 100. The writers built on it
are pinned byte for byte by `beast_composer`'s `smf_golden` and `midi_contracts`'
`scale_provider_golden`. The interfaces are exercised by the contracts that implement and call them,
in `midi_contracts` and `beast_contracts`.
