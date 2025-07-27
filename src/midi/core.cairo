use core::option::OptionTrait;
use core::traits::TryInto;
use koji::math::{Time, time_add, time_from_seconds, time_mul_by_factor, time_sub};
use koji::midi::types::{
    AfterTouch, ArpPattern, ControlChange, Direction, Message, Midi, Modes, NoteOff, NoteOn,
    PitchClass, PitchWheel, PolyTouch, ProgramChange, SetTempo, SystemExclusive, TimeSignature,
    VelocityCurve,
};

// Implementation of quantization function
fn round_to_nearest_nth(time: Time, grid_size: usize) -> Time {
    if grid_size == 0 {
        return time;
    }

    let grid_resolution: u64 = grid_size.into();

    // Equivalent to original: (time.mag / grid_resolution) * grid_resolution
    let rounded = (time / grid_resolution) * grid_resolution;

    // Calculate remainder: time.mag - rounded
    let remainder = time - rounded;
    let half_resolution = grid_resolution / 2;

    // Original logic: if remainder >= half_resolution, round up, else round down
    if remainder >= half_resolution {
        rounded + grid_resolution
    } else {
        rounded
    }
}

fn next_instrument_in_group(program: u8) -> u8 {
    // Simple instrument remapping - cycle through a few instruments
    if program < 127 {
        program + 1
    } else {
        0
    }
}
// use alexandria_data_structures::stack::{StackTrait, Felt252Stack, NullableStack};
// use alexandria_data_structures::array_ext::{ArrayTraitExt};

// use koji::midi::instruments::{
//     GeneralMidiInstrument, instrument_name, instrument_to_program_change,
//     program_change_to_instrument, next_instrument_in_group
// };
// use koji::midi::time::round_to_nearest_nth;
use koji::midi::modes::{mode_steps};
use koji::midi::pitch::{PitchClassTrait, keynum_to_pc, pc_to_keynum};
// use koji::midi::velocitycurve::{VelocityCurveTrait};

pub trait MidiTrait {
    /// =========== NOTE MANIPULATION ===========
    /// Instantiate a Midi.
    fn new() -> Midi;
    /// create music to be consumed by web app - maybe add flags to reverse notes
    fn music(
        reverse: i32,
        semitones: i32,
        grid_size: usize,
        factor: i32,
        new_tempo: u32,
        chanel: u32,
        steps: i32,
        tonic: PitchClass,
        modes: Modes,
    ) -> Midi;
    /// Append a message in a Midi object.
    fn append_message(self: @Midi, msg: Message) -> Midi;
    /// Transpose notes by a given number of semitones.
    fn transpose_notes(self: @Midi, semitones: i32) -> Midi;
    ///  Reverse the order of notes.
    fn reverse_notes(self: @Midi) -> Midi;
    /// Align notes to a given rhythmic grid.
    fn quantize_notes(self: @Midi, grid_size: usize) -> Midi;
    /// Extract notes within a specified pitch range.
    fn extract_notes(self: @Midi, note_range: usize) -> Midi;
    /// Change the duration of notes by a given factor
    fn change_note_duration(self: @Midi, factor: i32) -> Midi;
    /// =========== GLOBAL MANIPULATION ===========
    /// Alter the tempo of the Midi data.
    fn change_tempo(self: @Midi, new_tempo: u32) -> Midi;
    /// Change instrument patches based on a provided mapping
    fn remap_instruments(self: @Midi, chanel: u32) -> Midi;
    /// =========== ANALYSIS ===========
    /// Extract the tempo (in BPM) from the Midi data.
    fn get_bpm(self: @Midi) -> u32;
    /// Return statistics about notes (e.g., most frequent note, average note duration).
    /// =========== ADVANCED MANIPULATION ===========
    /// Add harmonies to existing melodies based on specified intervals.
    fn generate_harmony(self: @Midi, steps: i32, tonic: PitchClass, modes: Modes) -> Midi;
    /// Invert notes around a pivot point.
    fn invert_notes(self: @Midi, pivot_note: u8) -> Midi;
    /// Add notes one or more octaves higher or lower.
    fn octave_double(self: @Midi, octave_count: i32) -> Midi;
    /// Detect chords based on timing windows.
    fn detect_chords(self: @Midi, window_size: usize, minimum_notes: usize) -> Midi;
    /// Convert chords into arpeggios based on a given pattern.
    fn arpeggiate_chords(self: @Midi, pattern: ArpPattern) -> Midi;
    /// Add or modify dynamics (velocity) of notes based on a specified curve or pattern.
    fn edit_dynamics(self: @Midi, curve: VelocityCurve) -> Midi;
}

impl MidiImpl of MidiTrait {
    fn new() -> Midi {
        let empty_events: Array<Message> = array![];
        Midi { events: empty_events.span() }
    }

    // Current basic midi structure for playback
    fn music(
        reverse: i32,
        semitones: i32,
        grid_size: usize,
        factor: i32,
        new_tempo: u32,
        chanel: u32,
        steps: i32,
        tonic: PitchClass,
        modes: Modes,
    ) -> Midi {
        let mut eventlist = ArrayTrait::<Message>::new();

        // Set Instrument
        let outpc = ProgramChange { channel: 0, program: 7, time: time_from_seconds(6) };

        let pcmessage = Message::PROGRAM_CHANGE((outpc));

        // Set Tempo
        let newtempo = SetTempo { tempo: 0, time: Option::Some(time_from_seconds(0)) };

        // Create Notes
        let newnoteon1 = NoteOn { channel: 0, note: 60, velocity: 100, time: time_from_seconds(0) };

        let newnoteon2 = NoteOn { channel: 0, note: 21, velocity: 100, time: time_from_seconds(1) };

        let newnoteon3 = NoteOn {
            channel: 0, note: 90, velocity: 100, time: time_from_seconds(1) + 500000 // 1.5 seconds
        };

        let newnoteoff1 = NoteOff {
            channel: 0, note: 60, velocity: 100, time: time_from_seconds(2),
        };

        let newnoteoff2 = NoteOff {
            channel: 0, note: 21, velocity: 100, time: time_from_seconds(1) + 500000 // 1.5 seconds
        };

        let newnoteoff3 = NoteOff {
            channel: 0, note: 90, velocity: 100, time: time_from_seconds(5),
        };

        let tempomessage = Message::SET_TEMPO((newtempo));
        let notemessageon1 = Message::NOTE_ON((newnoteon1));
        let notemessageon2 = Message::NOTE_ON((newnoteon2));
        let notemessageon3 = Message::NOTE_ON((newnoteon3));
        let notemessageoff1 = Message::NOTE_OFF((newnoteoff1));
        let notemessageoff2 = Message::NOTE_OFF((newnoteoff2));
        let notemessageoff3 = Message::NOTE_OFF((newnoteoff3));

        eventlist.append(tempomessage);
        eventlist.append(pcmessage);
        eventlist.append(notemessageon1);
        eventlist.append(notemessageon2);
        eventlist.append(notemessageon3);
        eventlist.append(notemessageoff1);
        eventlist.append(notemessageoff2);
        eventlist.append(notemessageoff3);

        let mut basemidi = Midi { events: eventlist.span() };

        let mut finalMidi = basemidi
            .transpose_notes(semitones)
            .quantize_notes(grid_size)
            .change_note_duration(factor)
            .change_tempo(new_tempo)
            .remap_instruments(chanel)
            .generate_harmony(steps, tonic, modes);

        if reverse == 0 { //could be a bool
        } else {
            finalMidi = finalMidi.reverse_notes();
        }

        finalMidi
    }

    fn append_message(self: @Midi, msg: Message) -> Midi {
        let mut ev = *self.events;
        let mut output = array![];

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => { output.append(*currentevent); },
                Option::None(_) => { break; },
            };
        }

        output.append(msg);
        Midi { events: output.span() }
    }

    fn transpose_notes(self: @Midi, semitones: i32) -> Midi {
        let mut ev = self.clone().events;
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            let outnote = if semitones < 0 {
                                *note_on.note - semitones.try_into().unwrap()
                            } else {
                                *note_on.note + semitones.try_into().unwrap()
                            };
                            let newnote = NoteOn {
                                channel: *note_on.channel,
                                note: outnote,
                                velocity: *note_on.velocity,
                                time: *note_on.time,
                            };
                            let notemessage = Message::NOTE_ON((newnote));
                            eventlist.append(notemessage);
                        },
                        Message::NOTE_OFF(note_off) => {
                            let outnote = if semitones < 0 {
                                *note_off.note - semitones.try_into().unwrap()
                            } else {
                                *note_off.note + semitones.try_into().unwrap()
                            };

                            let newnote = NoteOff {
                                channel: *note_off.channel,
                                note: outnote,
                                velocity: *note_off.velocity,
                                time: *note_off.time,
                            };
                            let notemessage = Message::NOTE_OFF((newnote));
                            eventlist.append(notemessage);
                        },
                        Message::SET_TEMPO(_set_tempo) => { eventlist.append(*currentevent); },
                        Message::TIME_SIGNATURE(_time_signature) => {
                            eventlist.append(*currentevent);
                        },
                        Message::CONTROL_CHANGE(_control_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::PITCH_WHEEL(_pitch_wheel) => { eventlist.append(*currentevent); },
                        Message::AFTER_TOUCH(_after_touch) => { eventlist.append(*currentevent); },
                        Message::POLY_TOUCH(_poly_touch) => { eventlist.append(*currentevent); },
                        Message::PROGRAM_CHANGE(_program_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::SYSTEM_EXCLUSIVE(_system_exclusive) => {
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => { break; },
            };
        }

        Midi { events: eventlist.span() }
    }

    fn reverse_notes(self: @Midi) -> Midi {
        let mut ev = self.clone().events;
        let mut events_array = array![];

        // Copy events to array for reversal
        let mut events_copy = *self.events;
        while let Option::Some(event) = events_copy.pop_front() {
            events_array.append(*event);
        }

        // Manual reverse
        let mut rev_array = array![];
        let mut i = events_array.len();
        while i > 0 {
            i -= 1;
            rev_array.append(*events_array.at(i));
        }
        let mut rev = rev_array.span();

        let lastmsgtime = rev.pop_front();
        let firstmsgtime = ev.pop_front();
        let mut maxtime: Time = 0;
        let mut mintime: Time = 0;
        let mut eventlist = ArrayTrait::<Message>::new();

        //assign maxtime to the last message's time value in the Midi
        match lastmsgtime {
            Option::Some(currentev) => {
                match currentev {
                    Message::NOTE_ON(note_on) => { maxtime = *note_on.time; },
                    Message::NOTE_OFF(note_off) => { maxtime = *note_off.time; },
                    Message::SET_TEMPO(set_tempo) => {
                        match *set_tempo.time {
                            Option::Some(time) => { maxtime = time; },
                            Option::None => {},
                        }
                    },
                    Message::TIME_SIGNATURE(time_signature) => {
                        match *time_signature.time {
                            Option::Some(time) => { maxtime = time; },
                            Option::None => {},
                        }
                    },
                    Message::CONTROL_CHANGE(control_change) => { maxtime = *control_change.time; },
                    Message::PITCH_WHEEL(pitch_wheel) => { maxtime = *pitch_wheel.time; },
                    Message::AFTER_TOUCH(after_touch) => { maxtime = *after_touch.time; },
                    Message::POLY_TOUCH(poly_touch) => { maxtime = *poly_touch.time; },
                    Message::PROGRAM_CHANGE(program_change) => { maxtime = *program_change.time; },
                    Message::SYSTEM_EXCLUSIVE(system_exclusive) => {
                        maxtime = *system_exclusive.time;
                    },
                }
            },
            Option::None(_) => {},
        }

        //assign mintime to the first message's time value
        match firstmsgtime {
            Option::Some(currentev) => {
                match currentev {
                    Message::NOTE_ON(note_on) => { mintime = *note_on.time; },
                    Message::NOTE_OFF(note_off) => { mintime = *note_off.time; },
                    Message::SET_TEMPO(set_tempo) => {
                        match *set_tempo.time {
                            Option::Some(time) => { mintime = time; },
                            Option::None => {},
                        }
                    },
                    Message::TIME_SIGNATURE(time_signature) => {
                        match *time_signature.time {
                            Option::Some(time) => { mintime = time; },
                            Option::None => {},
                        }
                    },
                    Message::CONTROL_CHANGE(control_change) => { mintime = *control_change.time; },
                    Message::PITCH_WHEEL(pitch_wheel) => { mintime = *pitch_wheel.time; },
                    Message::AFTER_TOUCH(after_touch) => { mintime = *after_touch.time; },
                    Message::POLY_TOUCH(poly_touch) => { mintime = *poly_touch.time; },
                    Message::PROGRAM_CHANGE(program_change) => { mintime = *program_change.time; },
                    Message::SYSTEM_EXCLUSIVE(system_exclusive) => {
                        mintime = *system_exclusive.time;
                    },
                }
            },
            Option::None(_) => {},
        }

        loop {
            match rev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            let newnote = NoteOff {
                                channel: *note_on.channel,
                                note: *note_on.note,
                                velocity: *note_on.velocity,
                                time: time_add(time_sub(maxtime, *note_on.time), mintime),
                            };
                            let notemessage = Message::NOTE_OFF(newnote);
                            eventlist.append(notemessage);
                        },
                        Message::NOTE_OFF(note_off) => {
                            let newnote = NoteOn {
                                channel: *note_off.channel,
                                note: *note_off.note,
                                velocity: *note_off.velocity,
                                time: time_add(time_sub(maxtime, *note_off.time), mintime),
                            };
                            let notemessage = Message::NOTE_ON(newnote);
                            eventlist.append(notemessage);
                        },
                        Message::SET_TEMPO(set_tempo) => {
                            let scaledtempo = SetTempo {
                                tempo: *set_tempo.tempo,
                                time: match *set_tempo.time {
                                    Option::Some(time) => Option::Some(
                                        time_add(time_sub(maxtime, time), mintime),
                                    ),
                                    Option::None => Option::None,
                                },
                            };
                            let tempomessage = Message::SET_TEMPO(scaledtempo);
                            eventlist.append(tempomessage);
                        },
                        Message::TIME_SIGNATURE(time_signature) => {
                            let newtimesig = TimeSignature {
                                numerator: *time_signature.numerator,
                                denominator: *time_signature.denominator,
                                clocks_per_click: *time_signature.clocks_per_click,
                                time: match *time_signature.time {
                                    Option::Some(time) => Option::Some(
                                        time_add(time_sub(maxtime, time), mintime),
                                    ),
                                    Option::None => Option::None,
                                },
                            };
                            let tsmessage = Message::TIME_SIGNATURE(newtimesig);
                            eventlist.append(tsmessage);
                        },
                        Message::CONTROL_CHANGE(control_change) => {
                            let newcontrolchange = ControlChange {
                                channel: *control_change.channel,
                                control: *control_change.control,
                                value: *control_change.value,
                                time: time_add(time_sub(maxtime, *control_change.time), mintime),
                            };
                            let ccmessage = Message::CONTROL_CHANGE(newcontrolchange);
                            eventlist.append(ccmessage);
                        },
                        Message::PITCH_WHEEL(pitch_wheel) => {
                            let newpitchwheel = PitchWheel {
                                channel: *pitch_wheel.channel,
                                value: *pitch_wheel.value,
                                time: time_add(time_sub(maxtime, *pitch_wheel.time), mintime),
                            };
                            let pwmessage = Message::PITCH_WHEEL(newpitchwheel);
                            eventlist.append(pwmessage);
                        },
                        Message::AFTER_TOUCH(after_touch) => {
                            let newaftertouch = AfterTouch {
                                channel: *after_touch.channel,
                                value: *after_touch.value,
                                time: time_add(time_sub(maxtime, *after_touch.time), mintime),
                            };
                            let atmessage = Message::AFTER_TOUCH(newaftertouch);
                            eventlist.append(atmessage);
                        },
                        Message::POLY_TOUCH(poly_touch) => {
                            let newpolytouch = PolyTouch {
                                channel: *poly_touch.channel,
                                note: *poly_touch.note,
                                value: *poly_touch.value,
                                time: time_add(time_sub(maxtime, *poly_touch.time), mintime),
                            };
                            let ptmessage = Message::POLY_TOUCH(newpolytouch);
                            eventlist.append(ptmessage);
                        },
                        Message::PROGRAM_CHANGE(program_change) => {
                            let newprogchg = ProgramChange {
                                channel: *program_change.channel,
                                program: *program_change.program,
                                time: time_add(time_sub(maxtime, *program_change.time), mintime),
                            };
                            let pchgmessage = Message::PROGRAM_CHANGE(newprogchg);
                            eventlist.append(pchgmessage);
                        },
                        Message::SYSTEM_EXCLUSIVE(system_exclusive) => {
                            let newsysex = SystemExclusive {
                                data: *system_exclusive.data,
                                time: time_add(time_sub(maxtime, *system_exclusive.time), mintime),
                            };
                            let sysexgmessage = Message::SYSTEM_EXCLUSIVE(newsysex);
                            eventlist.append(sysexgmessage);
                        },
                    }
                },
                Option::None(_) => { break; },
            };
        }

        Midi { events: eventlist.span() }
    }

    fn quantize_notes(self: @Midi, grid_size: usize) -> Midi {
        let mut ev = self.clone().events;
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            let newnote = NoteOn {
                                channel: *note_on.channel,
                                note: *note_on.note,
                                velocity: *note_on.velocity,
                                time: round_to_nearest_nth(*note_on.time, grid_size),
                            };
                            let notemessage = Message::NOTE_ON((newnote));
                            eventlist.append(notemessage);
                        },
                        Message::NOTE_OFF(note_off) => {
                            let newnote = NoteOff {
                                channel: *note_off.channel,
                                note: *note_off.note,
                                velocity: *note_off.velocity,
                                time: round_to_nearest_nth(*note_off.time, grid_size),
                            };
                            let notemessage = Message::NOTE_OFF((newnote));
                            eventlist.append(notemessage);
                        },
                        Message::SET_TEMPO(_set_tempo) => { eventlist.append(*currentevent) },
                        Message::TIME_SIGNATURE(_time_signature) => {
                            eventlist.append(*currentevent)
                        },
                        Message::CONTROL_CHANGE(_control_change) => {
                            eventlist.append(*currentevent)
                        },
                        Message::PITCH_WHEEL(_pitch_wheel) => { eventlist.append(*currentevent) },
                        Message::AFTER_TOUCH(_after_touch) => { eventlist.append(*currentevent) },
                        Message::POLY_TOUCH(_poly_touch) => { eventlist.append(*currentevent) },
                        Message::PROGRAM_CHANGE(_program_change) => {
                            eventlist.append(*currentevent)
                        },
                        Message::SYSTEM_EXCLUSIVE(_system_exclusive) => {
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => { break; },
            };
        }

        // Create a new Midi object with the modified event list
        Midi { events: eventlist.span() }
    }

    fn extract_notes(self: @Midi, note_range: usize) -> Midi {
        let mut ev = self.clone().events;

        let middlec = 60;
        let mut lowerbound = 0;
        let mut upperbound = 127;

        if note_range < middlec {
            lowerbound = middlec - note_range;
        }
        if note_range + middlec < 127 {
            upperbound = middlec + note_range;
        }

        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            let currentnoteon = *note_on.note;
                            if currentnoteon > lowerbound.try_into().unwrap()
                                && currentnoteon < upperbound.try_into().unwrap() {
                                eventlist.append(*currentevent);
                            }
                        },
                        Message::NOTE_OFF(note_off) => {
                            let currentnoteoff = *note_off.note;
                            if currentnoteoff > lowerbound.try_into().unwrap()
                                && currentnoteoff < upperbound.try_into().unwrap() {
                                eventlist.append(*currentevent);
                            }
                        },
                        Message::SET_TEMPO(_set_tempo) => {},
                        Message::TIME_SIGNATURE(_time_signature) => {},
                        Message::CONTROL_CHANGE(_control_change) => {},
                        Message::PITCH_WHEEL(_pitch_wheel) => {},
                        Message::AFTER_TOUCH(_after_touch) => {},
                        Message::POLY_TOUCH(_poly_touch) => {},
                        Message::PROGRAM_CHANGE(_program_change) => {},
                        Message::SYSTEM_EXCLUSIVE(_system_exclusive) => {},
                    }
                },
                Option::None(_) => { break; },
            };
        }

        // Create a new Midi object with the modified event list
        Midi { events: eventlist.span() }
    }

    fn change_note_duration(self: @Midi, factor: i32) -> Midi {
        let mut ev = self.clone().events;
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            let newnote = NoteOn {
                                channel: *note_on.channel,
                                note: *note_on.note,
                                velocity: *note_on.velocity,
                                time: time_mul_by_factor(
                                    *note_on.time, factor.try_into().unwrap(), 1,
                                ),
                            };
                            let notemessage = Message::NOTE_ON((newnote));
                            eventlist.append(notemessage);
                        },
                        Message::NOTE_OFF(note_off) => {
                            let newnote = NoteOff {
                                channel: *note_off.channel,
                                note: *note_off.note,
                                velocity: *note_off.velocity,
                                time: time_mul_by_factor(
                                    *note_off.time, factor.try_into().unwrap(), 1,
                                ),
                            };
                            let notemessage = Message::NOTE_OFF((newnote));
                            eventlist.append(notemessage);
                        },
                        Message::SET_TEMPO(set_tempo) => {
                            let scaledtempo = SetTempo {
                                tempo: *set_tempo.tempo,
                                time: match *set_tempo.time {
                                    Option::Some(time) => Option::Some(
                                        time_mul_by_factor(time, factor.try_into().unwrap(), 1),
                                    ),
                                    Option::None => Option::None,
                                },
                            };
                            let tempomessage = Message::SET_TEMPO((scaledtempo));
                            eventlist.append(tempomessage);
                        },
                        Message::TIME_SIGNATURE(time_signature) => {
                            let newtimesig = TimeSignature {
                                numerator: *time_signature.numerator,
                                denominator: *time_signature.denominator,
                                clocks_per_click: *time_signature.clocks_per_click,
                                time: match *time_signature.time {
                                    Option::Some(time) => Option::Some(
                                        time_mul_by_factor(time, factor.try_into().unwrap(), 1),
                                    ),
                                    Option::None => Option::None,
                                },
                            };
                            let tsmessage = Message::TIME_SIGNATURE((newtimesig));
                            eventlist.append(tsmessage);
                        },
                        Message::CONTROL_CHANGE(control_change) => {
                            let newcontrolchange = ControlChange {
                                channel: *control_change.channel,
                                control: *control_change.control,
                                value: *control_change.value,
                                time: time_mul_by_factor(
                                    *control_change.time, factor.try_into().unwrap(), 1,
                                ),
                            };
                            let ccmessage = Message::CONTROL_CHANGE(newcontrolchange);
                            eventlist.append(ccmessage);
                        },
                        Message::PITCH_WHEEL(pitch_wheel) => {
                            let newpitchwheel = PitchWheel {
                                channel: *pitch_wheel.channel,
                                value: *pitch_wheel.value,
                                time: time_mul_by_factor(
                                    *pitch_wheel.time, factor.try_into().unwrap(), 1,
                                ),
                            };
                            let pwmessage = Message::PITCH_WHEEL(newpitchwheel);
                            eventlist.append(pwmessage);
                        },
                        Message::AFTER_TOUCH(after_touch) => {
                            let newaftertouch = AfterTouch {
                                channel: *after_touch.channel,
                                value: *after_touch.value,
                                time: time_mul_by_factor(
                                    *after_touch.time, factor.try_into().unwrap(), 1,
                                ),
                            };
                            let atmessage = Message::AFTER_TOUCH(newaftertouch);
                            eventlist.append(atmessage);
                        },
                        Message::POLY_TOUCH(poly_touch) => {
                            let newpolytouch = PolyTouch {
                                channel: *poly_touch.channel,
                                note: *poly_touch.note,
                                value: *poly_touch.value,
                                time: time_mul_by_factor(
                                    *poly_touch.time, factor.try_into().unwrap(), 1,
                                ),
                            };
                            let ptmessage = Message::POLY_TOUCH(newpolytouch);
                            eventlist.append(ptmessage);
                        },
                        Message::PROGRAM_CHANGE(program_change) => {
                            let newprogchg = ProgramChange {
                                channel: *program_change.channel,
                                program: *program_change.program,
                                time: time_mul_by_factor(
                                    *program_change.time, factor.try_into().unwrap(), 1,
                                ),
                            };
                            let pchgmessage = Message::PROGRAM_CHANGE(newprogchg);
                            eventlist.append(pchgmessage);
                        },
                        Message::SYSTEM_EXCLUSIVE(system_exclusive) => {
                            let newsysex = SystemExclusive {
                                data: *system_exclusive.data,
                                time: time_mul_by_factor(
                                    *system_exclusive.time, factor.try_into().unwrap(), 1,
                                ),
                            };
                            let sysexgmessage = Message::SYSTEM_EXCLUSIVE(newsysex);
                            eventlist.append(sysexgmessage);
                        },
                    }
                },
                Option::None(_) => { break; },
            };
        }

        // Create a new Midi object with the modified event list
        Midi { events: eventlist.span() }
    }

    fn change_tempo(self: @Midi, new_tempo: u32) -> Midi {
        // Create a clone of the MIDI events
        let mut ev = self.clone().events;

        // Create a new array to store the modified events
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            // Use pop_front to get the next event
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    // Process the current event
                    match currentevent {
                        Message::NOTE_ON(_note_on) => { eventlist.append(*currentevent); },
                        Message::NOTE_OFF(_note_off) => { eventlist.append(*currentevent); },
                        Message::SET_TEMPO(set_tempo) => {
                            // Create a new SetTempo message with the updated tempo
                            let tempo = SetTempo { tempo: new_tempo, time: *set_tempo.time };
                            let tempomessage = Message::SET_TEMPO((tempo));
                            eventlist.append(tempomessage);
                        },
                        Message::TIME_SIGNATURE(_time_signature) => {
                            eventlist.append(*currentevent);
                        },
                        Message::CONTROL_CHANGE(_control_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::PITCH_WHEEL(_pitch_wheel) => { eventlist.append(*currentevent); },
                        Message::AFTER_TOUCH(_after_touch) => { eventlist.append(*currentevent); },
                        Message::POLY_TOUCH(_poly_touch) => { eventlist.append(*currentevent); },
                        Message::PROGRAM_CHANGE(_program_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::SYSTEM_EXCLUSIVE(_system_exclusive) => {
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => {
                    // If there are no more events, break out of the loop
                    break;
                },
            };
        }

        // Create a new Midi object with the modified event list
        Midi { events: eventlist.span() }
    }

    fn remap_instruments(self: @Midi, chanel: u32) -> Midi {
        // Create a clone of the MIDI events
        let mut ev = self.clone().events;

        // Create a new array to store the modified events
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            // Use pop_front to get the next event
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    // Process the current event
                    match currentevent {
                        Message::NOTE_ON(_note_on) => { eventlist.append(*currentevent); },
                        Message::NOTE_OFF(_note_off) => { eventlist.append(*currentevent); },
                        Message::SET_TEMPO(_set_tempo) => {
                            // Create a new SetTempo message with the updated tempo
                            eventlist.append(*currentevent);
                        },
                        Message::TIME_SIGNATURE(_time_signature) => {
                            eventlist.append(*currentevent);
                        },
                        Message::CONTROL_CHANGE(_control_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::PITCH_WHEEL(_pitch_wheel) => { eventlist.append(*currentevent); },
                        Message::AFTER_TOUCH(_after_touch) => { eventlist.append(*currentevent); },
                        Message::POLY_TOUCH(_poly_touch) => { eventlist.append(*currentevent); },
                        Message::PROGRAM_CHANGE(program_change) => {
                            let newprogchg = ProgramChange {
                                channel: *program_change.channel,
                                program: next_instrument_in_group(*program_change.program),
                                time: *program_change.time,
                            };
                            let pchgmessage = Message::PROGRAM_CHANGE((newprogchg));
                            eventlist.append(pchgmessage);
                        },
                        Message::SYSTEM_EXCLUSIVE(_system_exclusive) => {
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => {
                    // If there are no more events, break out of the loop
                    break;
                },
            };
        }

        // Create a new Midi object with the modified event list
        Midi { events: eventlist.span() }
    }

    fn get_bpm(self: @Midi) -> u32 {
        // Iterate through the MIDI events, find and return the SetTempo message
        let mut ev = self.clone().events;
        let mut outtempo: u32 = 0;

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(_note_on) => {},
                        Message::NOTE_OFF(_note_off) => {},
                        Message::SET_TEMPO(set_tempo) => { outtempo = *set_tempo.tempo; },
                        Message::TIME_SIGNATURE(_time_signature) => {},
                        Message::CONTROL_CHANGE(_control_change) => {},
                        Message::PITCH_WHEEL(_pitch_wheel) => {},
                        Message::AFTER_TOUCH(_after_touch) => {},
                        Message::POLY_TOUCH(_poly_touch) => {},
                        Message::PROGRAM_CHANGE(_program_change) => {},
                        Message::SYSTEM_EXCLUSIVE(_system_exclusive) => {},
                    }
                },
                Option::None(_) => { break; },
            };
        }

        outtempo
    }

    fn generate_harmony(self: @Midi, steps: i32, tonic: PitchClass, modes: Modes) -> Midi {
        let mut ev = self.clone().events;
        let mut eventlist = ArrayTrait::<Message>::new();
        let currentmode = mode_steps(modes);

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            let outnote = keynum_to_pc(*note_on.note)
                                .modal_transposition(
                                    tonic,
                                    currentmode,
                                    steps.try_into().unwrap(),
                                    if steps < 0 {
                                        Direction::Up(())
                                    } else {
                                        Direction::Down(())
                                    },
                                );

                            let newnote = NoteOn {
                                channel: *note_on.channel,
                                note: outnote,
                                velocity: *note_on.velocity,
                                time: *note_on.time,
                            };

                            let notemessage = Message::NOTE_ON((newnote));
                            eventlist.append(notemessage);
                            //include original note
                            eventlist.append(*currentevent);
                        },
                        Message::NOTE_OFF(note_off) => {
                            let outnote = if steps < 0 {
                                *note_off.note - steps.try_into().unwrap()
                            } else {
                                *note_off.note + steps.try_into().unwrap()
                            };

                            let newnote = NoteOff {
                                channel: *note_off.channel,
                                note: outnote,
                                velocity: *note_off.velocity,
                                time: *note_off.time,
                            };

                            let notemessage = Message::NOTE_OFF((newnote));
                            eventlist.append(notemessage);
                            //include original note
                            eventlist.append(*currentevent);
                        },
                        Message::SET_TEMPO(_set_tempo) => { eventlist.append(*currentevent); },
                        Message::TIME_SIGNATURE(_time_signature) => {
                            eventlist.append(*currentevent);
                        },
                        Message::CONTROL_CHANGE(_control_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::PITCH_WHEEL(_pitch_wheel) => { eventlist.append(*currentevent); },
                        Message::AFTER_TOUCH(_after_touch) => { eventlist.append(*currentevent); },
                        Message::POLY_TOUCH(_poly_touch) => { eventlist.append(*currentevent); },
                        Message::PROGRAM_CHANGE(_program_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::SYSTEM_EXCLUSIVE(_system_exclusive) => {
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => { break; },
            };
        }

        Midi { events: eventlist.span() }
    }

    fn invert_notes(self: @Midi, pivot_note: u8) -> Midi {
        let mut ev = self.clone().events;
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            // Calculate inverted pitch
                            let original_note = *note_on.note;
                            let inverted_note = if original_note <= pivot_note {
                                pivot_note + (pivot_note - original_note)
                            } else {
                                // When original note is above pivot, we subtract in reverse
                                pivot_note - (original_note - pivot_note)
                            };

                            // Ensure note stays within MIDI range (0-127)
                            let final_note = if inverted_note > 127 {
                                127
                            } else {
                                inverted_note
                            };

                            let newnote = NoteOn {
                                channel: *note_on.channel,
                                note: final_note,
                                velocity: *note_on.velocity,
                                time: *note_on.time,
                            };
                            let notemessage = Message::NOTE_ON((newnote));
                            eventlist.append(notemessage);
                        },
                        Message::NOTE_OFF(note_off) => {
                            let original_note = *note_off.note;
                            let inverted_note = if original_note <= pivot_note {
                                pivot_note + (pivot_note - original_note)
                            } else {
                                pivot_note - (original_note - pivot_note)
                            };

                            // Ensure note stays within MIDI range (0-127)
                            let final_note = if inverted_note > 127 {
                                127
                            } else {
                                inverted_note
                            };

                            let newnote = NoteOff {
                                channel: *note_off.channel,
                                note: final_note,
                                velocity: *note_off.velocity,
                                time: *note_off.time,
                            };
                            let notemessage = Message::NOTE_OFF((newnote));
                            eventlist.append(notemessage);
                        },
                        _ => {
                            // Pass through all other message types unchanged
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => { break; },
            };
        }

        Midi { events: eventlist.span() }
    }

    fn octave_double(self: @Midi, octave_count: i32) -> Midi {
        let mut ev = self.clone().events;
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            // Get original pitch class from note
                            let original_pc = keynum_to_pc(*note_on.note);

                            // Create new PitchClass with adjusted octave
                            let new_octave: u8 = if octave_count < 0 {
                                if original_pc.octave >= (-octave_count).try_into().unwrap() {
                                    original_pc.octave - (-octave_count).try_into().unwrap()
                                } else {
                                    0
                                }
                            } else {
                                original_pc.octave + octave_count.try_into().unwrap()
                            };

                            let new_pc = PitchClass { note: original_pc.note, octave: new_octave };

                            let new_note = pc_to_keynum(new_pc);

                            let doubled_note = NoteOn {
                                channel: *note_on.channel,
                                note: new_note,
                                velocity: *note_on.velocity,
                                time: *note_on.time,
                            };
                            let note_message = Message::NOTE_ON((doubled_note));
                            eventlist.append(note_message);
                        },
                        Message::NOTE_OFF(note_off) => {
                            // Get original pitch class from note
                            let original_pc = keynum_to_pc(*note_off.note);

                            // Create new PitchClass with adjusted octave
                            let new_octave: u8 = if octave_count < 0 {
                                if original_pc.octave >= (-octave_count).try_into().unwrap() {
                                    original_pc.octave - (-octave_count).try_into().unwrap()
                                } else {
                                    0
                                }
                            } else {
                                original_pc.octave + octave_count.try_into().unwrap()
                            };

                            let new_pc = PitchClass { note: original_pc.note, octave: new_octave };

                            let new_note = pc_to_keynum(new_pc);

                            let doubled_note = NoteOff {
                                channel: *note_off.channel,
                                note: new_note,
                                velocity: *note_off.velocity,
                                time: *note_off.time,
                            };
                            let note_message = Message::NOTE_OFF((doubled_note));
                            eventlist.append(note_message);
                        },
                        _ => {
                            // All other message types are passed through unchanged
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => { break; },
            }
        }

        Midi { events: eventlist.span() }
    }

    fn detect_chords(self: @Midi, window_size: usize, minimum_notes: usize) -> Midi {
        let mut ev = self.clone().events;
        let mut eventlist = ArrayTrait::<Message>::new();
        let mut current_window = ArrayTrait::<Message>::new();
        let mut current_time: Time = 0;
        let window_size_time: Time = window_size.into();

        // First pass: Group notes into windows
        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            // Check if this note belongs in the current window
                            if *note_on.time - current_time <= window_size_time {
                                current_window.append(*currentevent);
                            } else {
                                // Process current window if it has enough notes
                                if current_window.len() >= minimum_notes {
                                    // Add all notes in the window as a chord
                                    let mut window_iter = current_window.span();
                                    loop {
                                        match window_iter.pop_front() {
                                            Option::Some(note) => { eventlist.append(*note); },
                                            Option::None => { break; },
                                        };
                                    };
                                }

                                // Start new window
                                current_window = ArrayTrait::new();
                                current_window.append(*currentevent);
                                current_time = *note_on.time;
                            }
                        },
                        Message::NOTE_OFF(_note_off) => {
                            // Add corresponding NOTE_OFF events for detected chords
                            if current_window.len() >= minimum_notes {
                                eventlist.append(*currentevent);
                            }
                        },
                        _ => {
                            // Pass through other message types
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => {
                    // Process final window
                    if current_window.len() >= minimum_notes {
                        let mut window_iter = current_window.span();
                        loop {
                            match window_iter.pop_front() {
                                Option::Some(note) => { eventlist.append(*note); },
                                Option::None => { break; },
                            };
                        };
                    }
                    break;
                },
            };
        }

        Midi { events: eventlist.span() }
    }

    fn arpeggiate_chords(self: @Midi, pattern: ArpPattern) -> Midi {
        panic(array!['not supported yet'])
    }

    fn edit_dynamics(self: @Midi, curve: VelocityCurve) -> Midi {
        let mut ev = self.clone().events;
        let mut _vcurve = curve.clone();
        let mut outvelocity = 0;
        let mut eventlist = ArrayTrait::<Message>::new();

        loop {
            match ev.pop_front() {
                Option::Some(currentevent) => {
                    match currentevent {
                        Message::NOTE_ON(note_on) => {
                            // TODO: Implement velocity curve functionality
                            // match vcurve.getlevelattime(*note_on.time) {
                            //     Option::Some(val) => { outvelocity = val; },
                            //     Option::None => { outvelocity = *note_on.velocity; }
                            // }
                            outvelocity = *note_on.velocity;

                            let newnote = NoteOn {
                                channel: *note_on.channel,
                                note: *note_on.note,
                                velocity: outvelocity,
                                time: *note_on.time,
                            };
                            let notemessage = Message::NOTE_ON(newnote);
                            eventlist.append(notemessage);
                        },
                        Message::NOTE_OFF(note_off) => {
                            // TODO: Implement velocity curve functionality
                            // match vcurve.getlevelattime(*note_off.time) {
                            //     Option::Some(val) => { outvelocity = val; },
                            //     Option::None => { outvelocity = *note_off.velocity; }
                            // }
                            outvelocity = *note_off.velocity;

                            let newnote = NoteOff {
                                channel: *note_off.channel,
                                note: *note_off.note,
                                velocity: outvelocity,
                                time: *note_off.time,
                            };
                            let notemessage = Message::NOTE_OFF(newnote);
                            eventlist.append(notemessage);
                        },
                        Message::SET_TEMPO(_set_tempo) => { eventlist.append(*currentevent); },
                        Message::TIME_SIGNATURE(_time_signature) => {
                            eventlist.append(*currentevent);
                        },
                        Message::CONTROL_CHANGE(_control_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::PITCH_WHEEL(_pitch_wheel) => { eventlist.append(*currentevent); },
                        Message::AFTER_TOUCH(_after_touch) => { eventlist.append(*currentevent); },
                        Message::POLY_TOUCH(_poly_touch) => { eventlist.append(*currentevent); },
                        Message::PROGRAM_CHANGE(_program_change) => {
                            eventlist.append(*currentevent);
                        },
                        Message::SYSTEM_EXCLUSIVE(_system_exclusive) => {
                            eventlist.append(*currentevent);
                        },
                    }
                },
                Option::None(_) => { break; },
            };
        }

        Midi { events: eventlist.span() }
    }
}
