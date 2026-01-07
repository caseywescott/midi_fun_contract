import { Midi, Header, Track } from '@tonejs/midi';
import {CairoParsedMidiEvent} from "../src/cairoToMidiParser";
import {mapCairoParsedMidiEventsToMidi} from "../src/cairoToMidiEvent";


describe('mapCairoParsedMidiEventsToMidi', () => {
    test('should correctly map CairoParsedMidiEvents to Midi format', () => {
        const mockCairoParsedMidiEvents: CairoParsedMidiEvent[] = [
            { type: 'header', ticksPerBeat: 384, deltaTime: 0, meta: true } as unknown as CairoParsedMidiEvent,
            { type: 'noteOn', channel: 1, noteNumber: 60, velocity: 100, deltaTime: 120 } as unknown as CairoParsedMidiEvent,
            { type: 'noteOff', channel: 1, noteNumber: 60, velocity: 0, deltaTime: 120 } as unknown as CairoParsedMidiEvent,
            { type: 'endOfTrack', deltaTime: 0, meta: true } as unknown as CairoParsedMidiEvent,
        ];

        const result = mapCairoParsedMidiEventsToMidi(mockCairoParsedMidiEvents);

        // Check if the header was correctly assigned
        expect(result.header.ppq).toBe(384);
        expect(result.tracks.length).toBe(1);
        //Those results are the same that library executed. NoteOn and NoteOff should be merged in a single note.
        expect(result.tracks[0].notes[0]).toHaveProperty('midi', 60)
        expect(result.tracks[0].notes[0]).toHaveProperty('velocity', 100/127)
        expect(result.tracks[0].notes[0]).toHaveProperty('ticks', 120)
    });

    test('should handle empty input gracefully', () => {
        const result = mapCairoParsedMidiEventsToMidi([]);
        expect(result).toBeInstanceOf(Midi);
        expect(result.tracks).toHaveLength(0);
    });

    test('should calculate absoluteTime for each event correctly', () => {
        const mockCairoParsedMidiEvents: CairoParsedMidiEvent[] = [
            { type: 'header', ticksPerBeat: 480, deltaTime: 0, meta: true } as unknown as CairoParsedMidiEvent,
            { type: 'noteOn', channel: 1, noteNumber: 60, velocity: 100, deltaTime: 50 } as unknown as CairoParsedMidiEvent,
            { type: 'noteOff', channel: 1, noteNumber: 60, velocity: 0, deltaTime: 70 } as unknown as CairoParsedMidiEvent,
            { type: 'noteOn', channel: 1, noteNumber: 87, velocity: 100, deltaTime: 13 } as unknown as CairoParsedMidiEvent,
            { type: 'noteOff', channel: 1, noteNumber: 87, velocity: 0, deltaTime: 5 } as unknown as CairoParsedMidiEvent,
            { type: 'endOfTrack', deltaTime: 0, meta: true } as unknown as CairoParsedMidiEvent,
        ];

        const result = mapCairoParsedMidiEventsToMidi(mockCairoParsedMidiEvents);

        expect(result.tracks.length).toBe(1);
        expect(result.tracks[0].notes.length).toBe(2);
        expect(result.tracks[0].notes[0]).toHaveProperty('ticks', 50); //50 = deltaTime off the first noteOn event
        expect(result.tracks[0].notes[1]).toHaveProperty('ticks', 133); // 133 = sum of the delta times before the second noteOn event

    });
});
