use core::array::{ArrayTrait, SpanTrait};
use core::option::OptionTrait;
use core::traits::TryInto;
use koji::math::Time;
use koji::midi::types::{ControlChange, Message, Midi, NoteOff, NoteOn, ProgramChange, SetTempo};

#[derive(Drop)]
struct MidiOutput {
    data: Array<u8>,
}

trait MidiOutputTrait {
    fn new() -> MidiOutput;
    fn append_byte(ref self: MidiOutput, value: u8);
    fn append_bytes(ref self: MidiOutput, values: Array<u8>);
    fn len(self: @MidiOutput) -> usize;
    fn get_data(self: @MidiOutput) -> Array<u8>;
}

impl MidiOutputImpl of MidiOutputTrait {
    fn new() -> MidiOutput {
        MidiOutput { data: ArrayTrait::new() }
    }

    fn append_byte(ref self: MidiOutput, value: u8) {
        self.data.append(value);
    }

    fn append_bytes(ref self: MidiOutput, mut values: Array<u8>) {
        loop {
            match values.pop_front() {
                Option::Some(value) => { self.data.append(value); },
                Option::None => { break; },
            };
        }
    }

    fn len(self: @MidiOutput) -> usize {
        self.data.len()
    }

    fn get_data(self: @MidiOutput) -> Array<u8> {
        let mut result = ArrayTrait::new();
        let mut data = self.data.span();
        loop {
            match data.pop_front() {
                Option::Some(value) => { result.append(*value); },
                Option::None => { break; },
            };
        }
        result
    }
}

/// Export MIDI object to binary MIDI file format
pub fn output_midi_object(midi: @Midi) -> Array<u8> {
    let mut output = MidiOutputTrait::new();

    // Add MIDI header chunk
    output.append_bytes(array![0x4D, 0x54, 0x68, 0x64]); // MThd
    output.append_bytes(array![0x00, 0x00, 0x00, 0x06]); // Length
    output.append_bytes(array![0x00, 0x00]); // Format 0
    output.append_bytes(array![0x00, 0x01]); // Number of tracks
    output.append_bytes(array![0x01, 0xE0]); // Division (480 PPQN)

    // Add track chunk header
    output.append_bytes(array![0x4D, 0x54, 0x72, 0x6B]); // MTrk

    // For simplicity, we'll create the track content first, then add length
    let mut track_output = MidiOutputTrait::new();

    let mut prev_time: Time = 0;
    let mut ev = *midi.events;

    loop {
        match ev.pop_front() {
            Option::Some(event) => {
                match event {
                    Message::NOTE_ON(note) => {
                        let delta: u32 = if *note.time >= prev_time {
                            (*note.time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = *note.time;
                        write_variable_length(delta, ref track_output);

                        track_output.append_byte(0x90 + (*note.channel % 16));
                        track_output.append_byte(*note.note);
                        track_output.append_byte(*note.velocity);
                    },
                    Message::NOTE_OFF(note) => {
                        let delta: u32 = if *note.time >= prev_time {
                            (*note.time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = *note.time;
                        write_variable_length(delta, ref track_output);

                        track_output.append_byte(0x80 + (*note.channel % 16));
                        track_output.append_byte(*note.note);
                        track_output.append_byte(*note.velocity);
                    },
                    Message::SET_TEMPO(tempo) => {
                        let time = match tempo.time {
                            Option::Some(t) => *t,
                            Option::None => prev_time,
                        };
                        let delta: u32 = if time >= prev_time {
                            (time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = time;

                        write_variable_length(delta, ref track_output);
                        track_output.append_bytes(array![0xFF, 0x51, 0x03]);

                        let tempo_val: u32 = (*tempo.tempo).into();
                        track_output.append_byte((tempo_val / 65536).try_into().unwrap());
                        track_output.append_byte(((tempo_val / 256) % 256).try_into().unwrap());
                        track_output.append_byte((tempo_val % 256).try_into().unwrap());
                    },
                    Message::PROGRAM_CHANGE(pc) => {
                        let delta: u32 = if *pc.time >= prev_time {
                            (*pc.time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = *pc.time;
                        write_variable_length(delta, ref track_output);

                        track_output.append_byte(0xC0 + (*pc.channel % 16));
                        track_output.append_byte(*pc.program);
                    },
                    Message::CONTROL_CHANGE(cc) => {
                        let delta: u32 = if *cc.time >= prev_time {
                            (*cc.time - prev_time).try_into().unwrap()
                        } else {
                            0
                        };
                        prev_time = *cc.time;
                        write_variable_length(delta, ref track_output);

                        track_output.append_byte(0xB0 + (*cc.channel % 16));
                        track_output.append_byte(*cc.control);
                        track_output.append_byte(*cc.value);
                    },
                    // Handle other message types as pass-through
                    _ => {},
                }
            },
            Option::None => { break; },
        };
    }

    // Write End of Track
    track_output.append_bytes(array![0x00, 0xFF, 0x2F, 0x00]);

    // Add track length
    let track_length = track_output.len();
    output.append_byte((track_length / 16777216).try_into().unwrap());
    output.append_byte(((track_length / 65536) % 256).try_into().unwrap());
    output.append_byte(((track_length / 256) % 256).try_into().unwrap());
    output.append_byte((track_length % 256).try_into().unwrap());

    // Add track data
    output.append_bytes(track_output.get_data());

    output.get_data()
}

fn write_variable_length(mut value: u32, ref output: MidiOutput) {
    if value == 0 {
        output.append_byte(0);
        return;
    }

    let mut buffer = ArrayTrait::new();

    // Build variable length encoding
    buffer.append((value % 128).try_into().unwrap());
    value = value / 128;

    loop {
        if value == 0 {
            break;
        }
        buffer.append(((value % 128) + 128).try_into().unwrap());
        value = value / 128;
    }

    // Write bytes in reverse order (manually reverse the array)
    let mut reversed = ArrayTrait::new();
    loop {
        match buffer.pop_front() {
            Option::Some(byte) => { reversed.append(byte); },
            Option::None => { break; },
        }
    }

    // Now append in reverse order
    let mut i = reversed.len();
    loop {
        if i == 0 {
            break;
        }
        i -= 1;
        match reversed.get(i) {
            Option::Some(byte) => { output.append_byte(*byte.unbox()); },
            Option::None => {},
        }
    }
}
