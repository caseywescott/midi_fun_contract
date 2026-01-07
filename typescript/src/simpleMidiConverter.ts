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
    
    // Set default tempo if no tempo event is found
    let tempo = 120; // Default BPM
    
    // Find tempo from events
    const tempoEvent = events.find(event => event.type === 'setTempo');
    if (tempoEvent && tempoEvent.microsecondsPerBeat) {
        // Convert microseconds per beat to BPM
        tempo = Math.round(60000000 / tempoEvent.microsecondsPerBeat);
    }
    
    // Set tempo
    midi.header.setTempo(tempo);
    
    // Create a single track
    const track = midi.addTrack();
    
    // Process events and add them to the track
    let currentTime = 0;
    
    events.forEach(event => {
        switch (event.type) {
            case 'noteOn':
                if (event.noteNumber !== undefined && event.velocity !== undefined) {
                    track.addNote({
                        midi: event.noteNumber,
                        time: currentTime / 1000, // Convert to seconds
                        duration: 0.5, // Default duration
                        velocity: event.velocity / 127 // Normalize velocity
                    });
                }
                break;
                
            case 'noteOff':
                // NoteOff events are handled automatically by the library
                break;
                
            case 'setTempo':
                // Tempo is already set in header
                break;
                
            case 'controlChange':
                if (event.controllerType !== undefined && event.value !== undefined) {
                    track.addCC({
                        number: event.controllerType,
                        value: event.value,
                        time: currentTime / 1000
                    });
                }
                break;
                
            case 'pitchWheel':
                if (event.value !== undefined) {
                    track.addPitchBend({
                        value: event.value,
                        time: currentTime / 1000
                    });
                }
                break;
        }
        
        // Update time based on delta time
        if (event.deltaTime !== undefined) {
            currentTime += event.deltaTime;
        }
    });
    
    // Save the MIDI file
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