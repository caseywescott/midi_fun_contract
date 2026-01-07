export interface CairoParsedMidiEvent {
    type: string;
    channel: number;
    noteNumber: number;
    velocity: number; //how 'hard' the note is pressure. If == 0 it's and noteOff event. But a noteOff can be != 0 too.
    deltaTime: number; //distance in between the event n and the event n - 1
    microsecondsPerBeat: number; //the tempo
    numerator: number; // with [numerador/denominator] you can generate the compass
    denominator: number;
    value: number;
    pitch: number;
    clock: number;
    absoluteTime: number; // events in cairo don't have the absolute time (they only have the deltaTime), and in @tonejs/midi yes. It's required to calculate it
    controllerType: number;
    ticksPerBeat: number; ////the same as ppq
    meta: boolean; //if the event it's for metadata
    programNumber: number; //required to change instrument type, for example 24 = Nylon String Guitar
    data: number[]; // For system exclusive data
}
/**
 * Parse a cairo event into a CairoParsedMidiEvent.
 * CairoParsedMidiEvent contains all possibles properties for a MidiEvent of the library @tonejs/midi
 * the name of the properties are the same of that library for compatibility
 */
export function parseEvent(cairoEvent: string): CairoParsedMidiEvent | null {
    const match = cairoEvent.match(/Message::([A-Z_]+)\((.+)\)/);
    if (!match) return null;

    const [, type, content] = match;
    let parsedEvent: Partial<CairoParsedMidiEvent> = { type: toCamelCase(type) };
    parsedEvent.deltaTime = parseTime(content.match(/time: (\d+)/)?.[1] || "");

    switch (type) {
        case "HEADER":
            parsedEvent.ticksPerBeat = parseInt(content.match(/ticksPerBeat: (\d+)/)?.[1] || "0");
            parsedEvent.meta = true
            break;
        case "NOTE_ON":
        case "NOTE_OFF":
            parsedEvent.channel = parseInt(content.match(/channel: (\d+)/)?.[1] || "0");
            parsedEvent.noteNumber = parseInt(content.match(/note: (\d+)/)?.[1] || "0");
            parsedEvent.velocity = parseInt(content.match(/velocity: (\d+)/)?.[1] || "0");
            // This is based on midi specification
            if (parsedEvent.velocity === 0) {
                parsedEvent.type = 'noteOff'
            }
            break;

        case "SET_TEMPO":
            const tempoValue = parseInt(content.match(/tempo: (\d+)/)?.[1] || "0");
            if (tempoValue !== undefined) {
                parsedEvent.microsecondsPerBeat = tempoValue;
            }
            const timeOptionMatch = content.match(/time: Option::Some\((\d+)\)/);
            if (timeOptionMatch) {
                parsedEvent.deltaTime = parseInt(timeOptionMatch[1]);
            } else {
                parsedEvent.deltaTime = undefined;
            }
            parsedEvent.meta = true
            break;

        case "TIME_SIGNATURE":
            parsedEvent.numerator = parseInt(content.match(/numerator: (\d+)/)?.[1] || "0");
            parsedEvent.denominator = parseInt(content.match(/denominator: (\d+)/)?.[1] || "0");
            parsedEvent.meta = true
            break;

        case "CONTROL_CHANGE":
            parsedEvent.channel = parseInt(content.match(/channel: (\d+)/)?.[1] || "0");
            parsedEvent.controllerType = parseInt(content.match(/control: (\d+)/)?.[1] || "0");
            parsedEvent.value = parseInt(content.match(/value: (\d+)/)?.[1] || "0");
            break;

        case "PITCH_WHEEL":
            parsedEvent.channel = parseInt(content.match(/channel: (\d+)/)?.[1] || "0");
            parsedEvent.value = parseInt(content.match(/pitch: (\d+)/)?.[1] || "0");
            break;

        case "AFTER_TOUCH":
            parsedEvent.channel = parseInt(content.match(/channel: (\d+)/)?.[1] || "0");
            parsedEvent.value = parseInt(content.match(/value: (\d+)/)?.[1] || "0");
            break;

        case "POLY_TOUCH":
            parsedEvent.channel = parseInt(content.match(/channel: (\d+)/)?.[1] || "0");
            parsedEvent.noteNumber = parseInt(content.match(/note: (\d+)/)?.[1] || "0");
            parsedEvent.value = parseInt(content.match(/value: (\d+)/)?.[1] || "0");
            break;

        case "PROGRAM_CHANGE":
            parsedEvent.channel = parseInt(content.match(/channel: (\d+)/)?.[1] || "0");
            parsedEvent.programNumber = parseInt(content.match(/program: (\d+)/)?.[1] || "0");
            break;

        case "SYSTEM_EXCLUSIVE":
            // Handle system exclusive data
            const dataMatch = content.match(/data: \[([^\]]+)\]/);
            if (dataMatch) {
                const dataString = dataMatch[1];
                const dataArray = dataString.split(',').map(s => parseInt(s.trim())).filter(n => !isNaN(n));
                parsedEvent.data = dataArray;
            }
            break;

        default:
            return null;
    }

    return parsedEvent as CairoParsedMidiEvent;
}

function toCamelCase(str: string): string {
    return str.toLowerCase().replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
}

function parseTime(timeStr: string): number {
    const match = timeStr.match(/(\d+)/);
    if (match) {
        return parseInt(match[1], 10);
    }
    return 0;
}