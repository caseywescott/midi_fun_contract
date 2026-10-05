# midi

Standard MIDI Files onchain: a Scarb `[lib]` package with no dependencies, no storage and no
syscalls. The Beast composer (`contracts/beast_music`) and the MIDI providers
(`contracts/midi_provider`, `contracts/beast_sound`) write their files with it.

```toml
[dependencies]
midi = { path = "../midi" }   # or a git dependency on this repository
```

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
are pinned byte for byte by `beast_music`'s `smf_golden` and `midi_provider`'s
`scale_provider_golden`.
