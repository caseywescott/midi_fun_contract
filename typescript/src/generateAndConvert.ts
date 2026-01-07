import { cairoToMidi } from './cairoToMidiEvent';
import { execSync } from 'child_process';
import * as fs from 'fs';
import * as path from 'path';

interface GenerateOptions {
    cairoOutputFile?: string;
    midiOutputFile?: string;
    generateCairoOnly?: boolean;
    generateMidiOnly?: boolean;
}

export function generateCairoAndConvertToMidi(options: GenerateOptions = {}): void {
    const {
        cairoOutputFile = 'generated_midi.cairo',
        midiOutputFile = 'generated_midi.mid',
        generateCairoOnly = false,
        generateMidiOnly = false
    } = options;

    console.log('🎵 MIDI Fun Contract - Cairo to MIDI Generator');
    console.log('==============================================');

    // Step 1: Generate Cairo code
    if (!generateMidiOnly) {
        console.log('\n📝 Step 1: Generating Cairo code...');
        try {
            // Run the Scarb test to generate Cairo code
            const scarbCommand = `SCARB_UI_VERBOSITY=quiet scarb test -- --filter midi_to_cairo_file_output_test 2>&1 | grep -v "running\|test\|gas usage\|test result" > ${cairoOutputFile}`;
            execSync(scarbCommand, { stdio: 'inherit' });
            
            if (fs.existsSync(cairoOutputFile)) {
                console.log(`✅ Cairo code generated successfully: ${cairoOutputFile}`);
                
                // Show preview of generated code
                const content = fs.readFileSync(cairoOutputFile, 'utf-8');
                const lines = content.split('\n');
                console.log('\n📄 Preview of generated Cairo code:');
                console.log('-----------------------------------');
                lines.slice(0, 10).forEach(line => console.log(line));
                if (lines.length > 10) {
                    console.log(`... and ${lines.length - 10} more lines`);
                }
            } else {
                throw new Error('Cairo file was not created');
            }
        } catch (error) {
            console.error('❌ Error generating Cairo code:', error);
            process.exit(1);
        }
    }

    // Step 2: Convert Cairo to MIDI
    if (!generateCairoOnly) {
        console.log('\n🎼 Step 2: Converting Cairo to MIDI...');
        try {
            if (!fs.existsSync(cairoOutputFile)) {
                throw new Error(`Cairo file not found: ${cairoOutputFile}`);
            }

            // Convert Cairo to MIDI using the existing function
            const midi = cairoToMidi(cairoOutputFile, midiOutputFile);
            
            console.log(`✅ MIDI file generated successfully: ${midiOutputFile}`);
            console.log(`📊 MIDI Stats:`);
            console.log(`   - Tracks: ${midi.tracks.length}`);
            console.log(`   - Duration: ${midi.duration.toFixed(2)} seconds`);
            console.log(`   - BPM: ${midi.header.tempos[0]?.bpm || 'N/A'}`);
            
            // Show track information
            midi.tracks.forEach((track, index) => {
                console.log(`   - Track ${index + 1}: ${track.notes.length} notes`);
            });

        } catch (error) {
            console.error('❌ Error converting Cairo to MIDI:', error);
            process.exit(1);
        }
    }

    console.log('\n🎉 Generation complete!');
    if (!generateMidiOnly) {
        console.log(`📁 Cairo file: ${cairoOutputFile}`);
    }
    if (!generateCairoOnly) {
        console.log(`🎵 MIDI file: ${midiOutputFile}`);
    }
}

// CLI interface
if (require.main === module) {
    const args = process.argv.slice(2);
    const options: GenerateOptions = {};
    
    for (let i = 0; i < args.length; i++) {
        switch (args[i]) {
            case '--cairo-only':
                options.generateCairoOnly = true;
                break;
            case '--midi-only':
                options.generateMidiOnly = true;
                break;
            case '--cairo-output':
                options.cairoOutputFile = args[++i];
                break;
            case '--midi-output':
                options.midiOutputFile = args[++i];
                break;
            case '--help':
            case '-h':
                console.log(`
🎵 MIDI Fun Contract - Cairo to MIDI Generator

Usage: npx ts-node src/generateAndConvert.ts [options]

Options:
  --cairo-only              Generate only Cairo code (skip MIDI conversion)
  --midi-only               Generate only MIDI (requires existing Cairo file)
  --cairo-output <file>     Specify Cairo output file (default: generated_midi.cairo)
  --midi-output <file>      Specify MIDI output file (default: generated_midi.mid)
  --help, -h                Show this help message

Examples:
  npx ts-node src/generateAndConvert.ts
  npx ts-node src/generateAndConvert.ts --cairo-only
  npx ts-node src/generateAndConvert.ts --cairo-output my_music.cairo --midi-output my_music.mid
`);
                process.exit(0);
                break;
        }
    }
    
    generateCairoAndConvertToMidi(options);
} 