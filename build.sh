#!/bin/bash

echo "Building glance..."
echo ""

# Build the app — capture full output for error checking
BUILD_LOG=$(mktemp)
xcodebuild \
    -scheme glance \
    -configuration Release \
    -derivedDataPath ./build \
    build \
    2>&1 | tee "$BUILD_LOG"

# Check if build succeeded
if grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo ""
else
    echo ""
    echo "Build failed. Errors:"
    grep "error:" "$BUILD_LOG" | head -20
    rm "$BUILD_LOG"
    exit 1
fi
rm "$BUILD_LOG"

# Kill running instance if any
killall glance 2>/dev/null || true
sleep 0.5

# Copy to Applications
rm -rf /Applications/glance.app
cp -r ./build/Build/Products/Release/glance.app /Applications/

echo "Installed to /Applications/glance.app"
echo ""

# Ask to launch
read -p "Launch now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    open /Applications/glance.app
    echo "Running! Look for the eye icon in your menu bar."
fi
