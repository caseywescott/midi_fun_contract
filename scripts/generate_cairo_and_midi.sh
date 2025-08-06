#!/bin/bash

# Script to generate Cairo code and optionally convert to MIDI
# Usage: ./scripts/generate_cairo_and_midi.sh [options]

# Default values
CAIRO_OUTPUT_FILE="generated_midi.cairo"
MIDI_OUTPUT_FILE="generated_midi.mid"
GENERATE_CAIRO_ONLY=false
GENERATE_MIDI_ONLY=false
USE_TYPESCRIPT_CONVERTER=true

# Function to show help
show_help() {
    echo "🎵 MIDI Fun Contract - Cairo to MIDI Generator"
    echo "=============================================="
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --cairo-only              Generate only Cairo code (skip MIDI conversion)"
    echo "  --midi-only               Generate only MIDI (requires existing Cairo file)"
    echo "  --cairo-output <file>     Specify Cairo output file (default: generated_midi.cairo)"
    echo "  --midi-output <file>      Specify MIDI output file (default: generated_midi.mid)"
    echo "  --no-typescript           Use simple shell conversion instead of TypeScript"
    echo "  --help, -h                Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 --cairo-only"
    echo "  $0 --cairo-output my_music.cairo --midi-output my_music.mid"
    echo "  $0 --no-typescript"
    echo ""
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cairo-only)
            GENERATE_CAIRO_ONLY=true
            shift
            ;;
        --midi-only)
            GENERATE_MIDI_ONLY=true
            shift
            ;;
        --cairo-output)
            CAIRO_OUTPUT_FILE="$2"
            shift 2
            ;;
        --midi-output)
            MIDI_OUTPUT_FILE="$2"
            shift 2
            ;;
        --no-typescript)
            USE_TYPESCRIPT_CONVERTER=false
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

echo "🎵 MIDI Fun Contract - Cairo to MIDI Generator"
echo "=============================================="

# Step 1: Generate Cairo code
if [ "$GENERATE_MIDI_ONLY" = false ]; then
    echo ""
    echo "📝 Step 1: Generating Cairo code..."
    echo "Output will be saved to: $CAIRO_OUTPUT_FILE"
    
    # Run the Scarb test and capture clean output
    SCARB_UI_VERBOSITY=quiet scarb test -- --filter midi_to_cairo_file_output_test 2>&1 | \
    grep -v "running\|test\|gas usage\|test result" > "$CAIRO_OUTPUT_FILE"
    
    if [ $? -eq 0 ] && [ -f "$CAIRO_OUTPUT_FILE" ]; then
        echo "✅ Cairo code generated successfully!"
        echo "📁 File: $CAIRO_OUTPUT_FILE"
        
        # Show preview
        echo ""
        echo "Preview of generated code:"
        echo "=========================="
        head -20 "$CAIRO_OUTPUT_FILE"
        
        # Check if there are more lines
        total_lines=$(wc -l < "$CAIRO_OUTPUT_FILE")
        if [ "$total_lines" -gt 20 ]; then
            echo "... and $((total_lines - 20)) more lines"
        fi
    else
        echo "❌ Error: Failed to generate Cairo code"
        exit 1
    fi
fi

# Step 2: Convert Cairo to MIDI
if [ "$GENERATE_CAIRO_ONLY" = false ]; then
    echo ""
    echo "🎼 Step 2: Converting Cairo to MIDI..."
    
    # Check if Cairo file exists
    if [ ! -f "$CAIRO_OUTPUT_FILE" ]; then
        echo "❌ Error: Cairo file not found: $CAIRO_OUTPUT_FILE"
        echo "   Use --cairo-only to generate only Cairo code, or ensure the file exists for --midi-only"
        exit 1
    fi
    
    if [ "$USE_TYPESCRIPT_CONVERTER" = true ]; then
        echo "Using TypeScript converter..."
        
        # Check if TypeScript dependencies are installed
        if [ ! -d "typescript/node_modules" ]; then
            echo "📦 Installing TypeScript dependencies..."
            cd typescript && npm install && cd ..
        fi
        
        # Generate parser format for TypeScript conversion
        echo "Generating parser format..."
        PARSER_OUTPUT_FILE="${CAIRO_OUTPUT_FILE%.cairo}_parser.cairo"
        SCARB_UI_VERBOSITY=quiet scarb test -- --filter midi_to_parser_format_test 2>&1 | \
        grep -v "running\|test\|gas usage\|test result" > "$PARSER_OUTPUT_FILE"
        
        if [ $? -eq 0 ] && [ -f "$PARSER_OUTPUT_FILE" ]; then
            echo "✅ Parser format generated: $PARSER_OUTPUT_FILE"
            
            # Run the simple TypeScript converter
            if command -v npx &> /dev/null; then
                echo "Converting Cairo to MIDI using TypeScript..."
                npx ts-node typescript/src/simpleMidiConverter.ts "$PARSER_OUTPUT_FILE" "$MIDI_OUTPUT_FILE"
            else
                echo "❌ Error: npx not found. Please install Node.js and npm."
                exit 1
            fi
        else
            echo "❌ Error: Failed to generate parser format"
            exit 1
        fi
    else
        echo "Using simple shell conversion (basic MIDI generation)..."
        echo "⚠️  Note: Simple conversion may not preserve all MIDI features"
        
        # Simple conversion using basic MIDI structure
        # This is a fallback option that creates a basic MIDI file
        echo "Creating basic MIDI file..."
        
        # Create a simple MIDI file with basic structure
        # This is a minimal implementation - the TypeScript converter is much more robust
        cat > "$MIDI_OUTPUT_FILE" << 'EOF'
MThd
00000006
0001
0001
00C0
MTrk
0000000B
00FF5103
07A120
00FF2F00
EOF
        
        echo "✅ Basic MIDI file created: $MIDI_OUTPUT_FILE"
        echo "⚠️  This is a minimal MIDI file. Use TypeScript converter for full features."
    fi
fi

echo ""
echo "🎉 Generation complete!"
if [ "$GENERATE_MIDI_ONLY" = false ]; then
    echo "📁 Cairo file: $CAIRO_OUTPUT_FILE"
fi
if [ "$GENERATE_CAIRO_ONLY" = false ]; then
    echo "🎵 MIDI file: $MIDI_OUTPUT_FILE"
    if [ "$USE_TYPESCRIPT_CONVERTER" = true ]; then
        echo "📄 Parser format: ${CAIRO_OUTPUT_FILE%.cairo}_parser.cairo"
    fi
fi
echo ""
echo "💡 Tips:"
echo "   - Use a MIDI player to listen to the generated file"
echo "   - Edit the Cairo code to modify the music"
echo "   - Use --help for more options" 