import {Header, Midi, Track} from "@tonejs/midi";
import * as fs from "fs";
import {parseEvent, CairoParsedMidiEvent} from './cairoToMidiParser'
import {MidiData, MidiEvent, MidiHeader} from "midi-file";

export function cairoToMidi(cairoFilePath: string, outputFile: string): Midi {
    const fileContent = fs.readFileSync(cairoFilePath, "utf-8");
    const lines = fileContent.split("\n");

    const cairoParsedMidiEvents:CairoParsedMidiEvent[] = [];

    lines.forEach((line) => {
        const cairoParsedEvent = parseEvent(line);
        if (cairoParsedEvent) {
            cairoParsedMidiEvents.push(cairoParsedEvent);
        }
    });

    const midi = mapCairoParsedMidiEventsToMidi(cairoParsedMidiEvents);

    const midiBuffer = midi.toArray();
    fs.writeFileSync(outputFile, new Uint8Array(midiBuffer));

    return midi
}

/**
 * This function is strongly coupled to the current implementation of @tonejs/midi
 * it tries to adopt cairoParsedMidiEvents inorder to use the parsing logic of the library
 */

export function mapCairoParsedMidiEventsToMidi(cairoParsedMidiEvents: CairoParsedMidiEvent[]): Midi {
    const midi = new Midi();
    //Base case returns an empty midi
    if (!cairoParsedMidiEvents || cairoParsedMidiEvents.length === 0) {
        return midi
    }
    const parsedHeader = cairoParsedMidiEvents.shift();
    const tracks = splitByEndOfTrack(cairoParsedMidiEvents)

    tracks.forEach(track => {
        // CairoParsedMidiEvent has a deltaTime property that means the distance between the current event and the previous one
        // @tonejs/midi needs the absoluteTime of the event, so, this piece of code calculates the absolute time based on deltas
        let currentTicks = 0;
        track.forEach((event, idx) => {
            currentTicks += event.deltaTime;
            event.absoluteTime = currentTicks;
        });
    })

    const midiData: MidiData = {
        header: parsedHeader as unknown as MidiHeader,
        tracks: tracks as unknown as Array<MidiEvent[]>
    }

    // Events like setTempo, timeSignature, keySignature, header are used here
    midi.header = new Header(midiData)

    tracks.forEach(track => {
        // Events like noteOn, noteOff, controller, end of track are used here
        const midiTrack = new Track(track as unknown as MidiEvent[], midi.header)
        midi.tracks.push(midiTrack)
    })

    return midi
}

/**
 * CairoParsedMidiEvent[] includes an endOfTrack event.
 * This function detect those events to split the events into tracks
 */
export function splitByEndOfTrack(events: CairoParsedMidiEvent[]): CairoParsedMidiEvent[][] {
    const result: CairoParsedMidiEvent[][] = [];
    let currentTrack: CairoParsedMidiEvent[] = [];

    for (const event of events) {
        currentTrack.push(event);

        if (event.type === "endOfTrack") {
            result.push(currentTrack);
            currentTrack = [];
        }
    }

    return result;
}