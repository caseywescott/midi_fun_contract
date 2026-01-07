import { parseEvent } from '../src/cairoToMidiParser';

describe('parseEvent', () => {
    test('should return null for invalid events', () => {
        expect(parseEvent("InvalidEventString")).toBeNull();
        expect(parseEvent("Message::UNKNOWN_TYPE()")).toBeNull();
    });

    test('should correctly parse a HEADER event', () => {
        const cairoEvent = 'Message::HEADER(Header { ticksPerBeat: 480 }),';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'header',
            ticksPerBeat: 480,
            meta: true,
            deltaTime: 0
        });
    });

    test('should correctly parse a NOTE_ON event', () => {
        const cairoEvent = 'Message::NOTE_ON(NoteOn { channel: 0, note: 60, velocity: 100, time: 184 })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'noteOn',
            channel: 0,
            noteNumber: 60,
            velocity: 100,
            deltaTime: 184
        });
    });

    test('should change the type to "noteOff" when velocity is 0 in NOTE_ON', () => {
        const cairoEvent = 'Message::NOTE_ON(NoteOn { channel: 0, note: 60, velocity: 0, time: 189 })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'noteOff',
            channel: 0,
            noteNumber: 60,
            velocity: 0,
            deltaTime: 189
        });
    });

    test('should correctly parse a SET_TEMPO event', () => {
        const cairoEvent = 'Message::SET_TEMPO(SetTempo { tempo: 600000, time: Option::Some(0) })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'setTempo',
            microsecondsPerBeat: 600000,
            deltaTime: 0,
            meta: true
        });
    });

    test('should correctly parse a TIME_SIGNATURE event', () => {
        const cairoEvent = 'Message::TIME_SIGNATURE(TimeSignature { numerator: 4, denominator: 4, clocks_per_click: 24, time: None })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'timeSignature',
            numerator: 4,
            denominator: 4,
            deltaTime: 0,
            meta: true
        });
    });

    test('should correctly parse a CONTROL_CHANGE event', () => {
        const cairoEvent = 'Message::CONTROL_CHANGE(ControlChange { channel: 0, control: 7, value: 100, time: 0 })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'controlChange',
            channel: 0,
            controllerType: 7,
            value: 100,
            deltaTime: 0
        });
    });

    test('should correctly parse a PITCH_WHEEL event', () => {
        const cairoEvent = 'Message::PITCH_WHEEL(PitchWheel { channel: 0, pitch: 8192, time: 0 })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'pitchWheel',
            channel: 0,
            value: 8192,
            deltaTime: 0
        });
    });

    test('should correctly parse an AFTER_TOUCH event', () => {
        const cairoEvent = 'Message::AFTER_TOUCH(AfterTouch { channel: 0, value: 64, time: 0 })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'afterTouch',
            channel: 0,
            value: 64,
            deltaTime: 0
        });
    });

    test('should correctly parse a POLY_TOUCH event', () => {
        const cairoEvent = 'Message::POLY_TOUCH(PolyTouch { channel: 0, note: 60, value: 64, time: 0 })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'polyTouch',
            channel: 0,
            noteNumber: 60,
            value: 64,
            deltaTime: 0
        });
    });

    test('should correctly parse a PROGRAM_CHANGE event', () => {
        const cairoEvent = 'Message::PROGRAM_CHANGE(ProgramChange { channel: 0, program: 24, time: 0 })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'programChange',
            channel: 0,
            programNumber: 24,
            deltaTime: 0
        });
    });

    test('should correctly parse a SYSTEM_EXCLUSIVE event', () => {
        const cairoEvent = 'Message::SYSTEM_EXCLUSIVE(SystemExclusive { data: [240, 1, 2, 3, 247], time: 0 })';
        const result = parseEvent(cairoEvent);
        expect(result).toEqual({
            type: 'systemExclusive',
            data: [240, 1, 2, 3, 247],
            deltaTime: 0
        });
    });
});
