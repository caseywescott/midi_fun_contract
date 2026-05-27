import { Midi } from "@tonejs/midi";
import * as fs from "fs";
import { parseEvent, CairoParsedMidiEvent } from './cairoToMidiParser';

export function simpleCairoToMidi(cairoFilePath: string, outputFile: string): Midi {
    const fileContent = fs.readFileSync(cairoFilePath, "utf-8");
    const lines = fileContent.split("\n").filter(line => line.trim() !== "");

    const cairoParsedMidiEvents: CairoParsedMidiEvent[] = [];

    lines.forEach((line) => {
        const cairoParsedEvent = parseEvent(line);
        if (cairoParsedEvent) {
            cairoParsedMidiEvents.push(cairoParsedEvent);
        }
    });

    return createMidiFromEvents(cairoParsedMidiEvents, outputFile);
}

function createMidiFromEvents(events: CairoParsedMidiEvent[], outputFile: string): Midi {
    const midi = new Midi();

    // Find tempo from events (microsecondsPerBeat → BPM)
    let tempoUs = 500000; // default: 120 BPM
    const tempoEvent = events.find(event => event.type === 'setTempo');
    if (tempoEvent && tempoEvent.microsecondsPerBeat) {
        tempoUs = tempoEvent.microsecondsPerBeat;
    }
    midi.header.setTempo(Math.round(60000000 / tempoUs));

    // One track per MIDI channel — created on demand
    const tracksByChannel = new Map<number, ReturnType<typeof midi.addTrack>>();
    const getTrack = (channel: number) => {
        if (!tracksByChannel.has(channel)) {
            const t = midi.addTrack();
            t.channel = channel;
            tracksByChannel.set(channel, t);
        }
        return tracksByChannel.get(channel)!;
    };

    // Cairo `time` is an absolute position in microseconds.
    // The parser stores it in the `deltaTime` field (misnamed).
    // Key = "channel-noteNumber" so the same pitch on different channels never collide.
    const openNotes = new Map<string, { startUs: number; velocity: number; channel: number }>();

    events.forEach(event => {
        // `deltaTime` holds the absolute time in µs from the Cairo `time` field
        const absoluteUs: number = event.deltaTime ?? 0;
        const absoluteSec = absoluteUs / 1_000_000;
        const ch = event.channel ?? 0;

        switch (event.type) {
            case 'noteOn':
                // Record the start time and velocity; emit the note when we see NOTE_OFF
                openNotes.set(`${ch}-${event.noteNumber}`, {
                    startUs: absoluteUs,
                    velocity: event.velocity,
                    channel: ch,
                });
                break;

            case 'noteOff': {
                const key = `${ch}-${event.noteNumber}`;
                const open = openNotes.get(key);
                if (open !== undefined) {
                    const startSec = open.startUs / 1_000_000;
                    const durationSec = absoluteSec - startSec;
                    getTrack(open.channel).addNote({
                        midi: event.noteNumber,
                        time: startSec,
                        duration: durationSec > 0 ? durationSec : 0.01,
                        velocity: open.velocity / 127,
                    });
                    openNotes.delete(key);
                }
                break;
            }

            case 'controlChange':
                if (event.controllerType !== undefined && event.value !== undefined) {
                    getTrack(ch).addCC({ number: event.controllerType, value: event.value, time: absoluteSec });
                }
                break;

            case 'pitchWheel':
                if (event.value !== undefined) {
                    getTrack(ch).addPitchBend({ value: event.value, time: absoluteSec });
                }
                break;
        }
    });

    // Emit any NOTE_ONs that had no matching NOTE_OFF (give them a short default duration)
    openNotes.forEach((open, key) => {
        const noteNumber = parseInt(key.split('-')[1]);
        getTrack(open.channel).addNote({
            midi: noteNumber,
            time: open.startUs / 1_000_000,
            duration: 0.5,
            velocity: open.velocity / 127,
        });
    });

    const midiBuffer = midi.toArray();
    fs.writeFileSync(outputFile, new Uint8Array(midiBuffer));

    return midi;
}

// CLI interface
if (require.main === module) {
    const args = process.argv.slice(2);
    
    if (args.length < 2) {
        console.log(`
🎵 Simple Cairo to MIDI Converter

Usage: npx ts-node src/simpleMidiConverter.ts <cairo_file> <midi_output>

Example:
  npx ts-node src/simpleMidiConverter.ts generated_midi_parser.cairo output.mid
`);
        process.exit(1);
    }
    
    const [cairoFile, midiFile] = args;
    
    try {
        const midi = simpleCairoToMidi(cairoFile, midiFile);
        console.log(`✅ MIDI file created successfully: ${midiFile}`);
        console.log(`📊 MIDI Stats:`);
        console.log(`   - Tracks: ${midi.tracks.length}`);
        console.log(`   - Duration: ${midi.duration.toFixed(2)} seconds`);
        console.log(`   - BPM: ${midi.header.tempos[0]?.bpm || 'N/A'}`);
        
        midi.tracks.forEach((track, index) => {
            console.log(`   - Track ${index + 1}: ${track.notes.length} notes`);
        });
    } catch (error) {
        console.error('❌ Error converting Cairo to MIDI:', error);
        process.exit(1);
    }
} 