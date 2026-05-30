#!/bin/bash
set -e

# Build ClaudeStatusLight from source
# Prerequisites: macOS with Xcode Command Line Tools (swiftc)

OUTPUT="${1:-ClaudeStatusLight.app/Contents/MacOS/ClaudeStatusLight}"

echo "Building ClaudeStatusLight..."
swiftc -o "$OUTPUT" main.swift

echo "Copying icon..."
cp AppIcon.icns ClaudeStatusLight.app/Contents/Resources/AppIcon.icns

echo "Done → $OUTPUT"
echo "Run: open ClaudeStatusLight.app"
