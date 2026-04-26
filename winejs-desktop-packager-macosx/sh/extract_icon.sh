#!/bin/bash
EXE_FILE="$1"
OUTPUT_DIR="$2"

echo "🔍 Extracting icons from: $(basename "$EXE_FILE")"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Extract icons using icoutils
TEMP_ICO_DIR="$OUTPUT_DIR/ico_temp"
mkdir -p "$TEMP_ICO_DIR"

# Extract all icon resources
wrestool --extract --type=14 "$EXE_FILE" -o "$TEMP_ICO_DIR/" 2>/dev/null

ICO_COUNT=$(find "$TEMP_ICO_DIR" -name "*.ico" 2>/dev/null | wc -l)
if [ "$ICO_COUNT" -eq 0 ]; then
    wrestool --extract --type=group_icon "$EXE_FILE" -o "$TEMP_ICO_DIR/" 2>/dev/null
    ICO_COUNT=$(find "$TEMP_ICO_DIR" -name "*.ico" 2>/dev/null | wc -l)
fi

echo "📦 Found $ICO_COUNT ICO resource(s)"

PNG_TOTAL=0
if [ "$ICO_COUNT" -gt 0 ]; then
    for ico in "$TEMP_ICO_DIR"/*.ico; do
        if [ -f "$ico" ]; then
            icotool -x "$ico" -o "$OUTPUT_DIR/" 2>/dev/null
            PNG_EXTRACTED=$(find "$OUTPUT_DIR" -name "*.png" -newer "$ico" 2>/dev/null | wc -l)
            PNG_TOTAL=$((PNG_TOTAL + PNG_EXTRACTED))
            echo "  ✓ Extracted $PNG_EXTRACTED PNG(s) from $(basename "$ico")"
        fi
    done
fi

rm -rf "$TEMP_ICO_DIR"

PNG_COUNT=$(find "$OUTPUT_DIR" -name "*.png" 2>/dev/null | wc -l)

if [ "$PNG_COUNT" -gt 0 ]; then
    echo "✅ Total PNGs extracted: $PNG_COUNT"
    
    LARGEST=$(find "$OUTPUT_DIR" -name "*.png" -type f -exec ls -S {} \; | head -1)
    LARGEST_SIZE=$(du -h "$LARGEST" 2>/dev/null | cut -f1)
    LARGEST_DIMS=$(file "$LARGEST" | grep -oE '[0-9]+ x [0-9]+' || echo "unknown")
    
    echo "📏 Largest icon: $(basename "$LARGEST") (${LARGEST_DIMS}, ${LARGEST_SIZE})"
    
    > "$OUTPUT_DIR/icon_list.txt"
    for png in $(find "$OUTPUT_DIR" -name "*.png" -type f | sort); do
        DIMS=$(file "$png" | grep -oE '[0-9]+ x [0-9]+' || echo "unknown")
        SIZE=$(du -h "$png" | cut -f1)
        echo "$(basename "$png")|$DIMS|$SIZE|$png" >> "$OUTPUT_DIR/icon_list.txt"
    done
    
    echo "ICON_COUNT=$PNG_COUNT"
    echo "LARGEST_ICON=$LARGEST"
    exit 0
else
    echo "❌ No icons found in EXE"
    echo "ICON_COUNT=0"
    exit 1
fi
