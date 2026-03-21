#!/bin/bash
set -e

VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
APP_NAME="glance"
DMG_NAME="Glance-${VERSION}.dmg"
BUILD_DIR="./build"
RELEASE_DIR="./release"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"

echo "=== Building Glance v${VERSION} ==="
echo ""

# Generate Xcode project if needed
if [ ! -f "${APP_NAME}.xcodeproj/project.pbxproj" ]; then
    echo "Generating Xcode project..."
    xcodegen generate
    echo ""
fi

# Build
echo "Compiling..."
BUILD_LOG=$(mktemp)
xcodebuild \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build \
    2>&1 | tee "$BUILD_LOG"

if ! grep -q "BUILD SUCCEEDED" "$BUILD_LOG"; then
    echo ""
    echo "Build failed."
    grep "error:" "$BUILD_LOG" | head -20
    rm "$BUILD_LOG"
    exit 1
fi
rm "$BUILD_LOG"

echo ""
echo "Build succeeded."

# Prepare release directory
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Check for create-dmg (nicer DMGs with background, icon layout, etc.)
if command -v create-dmg &> /dev/null; then
    echo "Creating DMG with create-dmg..."
    create-dmg \
        --volname "Glance" \
        --volicon "${APP_PATH}/Contents/Resources/AppIcon.icns" \
        --window-pos 200 120 \
        --window-size 660 400 \
        --icon-size 128 \
        --icon "$APP_NAME.app" 180 190 \
        --hide-extension "$APP_NAME.app" \
        --app-drop-link 480 190 \
        --no-internet-enable \
        "${RELEASE_DIR}/${DMG_NAME}" \
        "$APP_PATH" \
        2>/dev/null || {
            # create-dmg returns 2 on "image already exists" — retry after cleanup
            rm -f "${RELEASE_DIR}/${DMG_NAME}"
            create-dmg \
                --volname "Glance" \
                --window-pos 200 120 \
                --window-size 660 400 \
                --icon-size 128 \
                --icon "$APP_NAME.app" 180 190 \
                --hide-extension "$APP_NAME.app" \
                --app-drop-link 480 190 \
                --no-internet-enable \
                "${RELEASE_DIR}/${DMG_NAME}" \
                "$APP_PATH"
        }
else
    echo "Creating DMG..."
    echo "(Tip: brew install create-dmg for a nicer DMG with drag-to-Applications layout)"
    echo ""

    # Create a temporary directory for DMG contents
    DMG_STAGING=$(mktemp -d)
    cp -r "$APP_PATH" "$DMG_STAGING/"
    ln -s /Applications "$DMG_STAGING/Applications"

    # Create DMG
    hdiutil create \
        -volname "Glance" \
        -srcfolder "$DMG_STAGING" \
        -ov \
        -format UDZO \
        "${RELEASE_DIR}/${DMG_NAME}"

    rm -rf "$DMG_STAGING"
fi

echo ""
echo "DMG: ${RELEASE_DIR}/${DMG_NAME}"
echo ""

# Upload to GitHub
if ! command -v gh &> /dev/null; then
    echo "gh CLI not found — skipping GitHub release."
    echo "Install with: brew install gh"
    echo ""
    echo "To install locally: open the DMG and drag Glance to Applications."
    exit 0
fi

TAG="v${VERSION}"

if gh release view "$TAG" &> /dev/null; then
    echo "Release ${TAG} already exists. Uploading DMG as additional asset..."
    gh release upload "$TAG" "${RELEASE_DIR}/${DMG_NAME}" --clobber
else
    echo "Creating GitHub release ${TAG}..."
    gh release create "$TAG" \
        "${RELEASE_DIR}/${DMG_NAME}" \
        --title "Glance ${VERSION}" \
        --generate-notes
fi

echo ""
echo "=== Done ==="
echo "Release: $(gh release view "$TAG" --json url -q .url)"
