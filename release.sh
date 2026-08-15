#!/bin/bash
set -e

VERSION=$(grep 'MARKETING_VERSION' project.yml | head -1 | sed 's/.*: *"\(.*\)"/\1/')
APP_NAME="glance"
DMG_NAME="Glance-${VERSION}.dmg"
BUILD_DIR="./build"
RELEASE_DIR="./release"
APP_PATH="${BUILD_DIR}/Build/Products/Release/${APP_NAME}.app"
ENTITLEMENTS="glance/glance.entitlements"

# --no-upload: skip the GitHub-release section (build + sign/notarize only, for dry runs)
NO_UPLOAD=false
for arg in "$@"; do
    case "$arg" in
        --no-upload)
            NO_UPLOAD=true
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--no-upload]"
            exit 1
            ;;
    esac
done

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

# Look for a "Developer ID Application" signing identity. SIGN_IDENTITY overrides detection.
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.+)"/\1/')
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo ""
    echo "=== Signing (identity: ${SIGN_IDENTITY}) ==="
    codesign --force --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$SIGN_IDENTITY" \
        "$APP_PATH"
    codesign --verify --strict --verbose=2 "$APP_PATH"
    echo "App signed."
else
    echo ""
    echo "No 'Developer ID Application' signing identity found — building unsigned (ad-hoc) as before."
    echo "See RELEASING.md for one-time Apple Developer / notarization setup."
fi

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

# Sign + notarize the DMG if we have a Developer ID identity
if [ -n "$SIGN_IDENTITY" ]; then
    echo "=== Notarizing ==="

    echo "Signing DMG..."
    codesign --force --sign "$SIGN_IDENTITY" "${RELEASE_DIR}/${DMG_NAME}"

    NOTARY_PROFILE="${NOTARY_PROFILE:-glance-notary}"
    echo "Submitting to notary service (keychain profile: ${NOTARY_PROFILE})..."
    NOTARY_LOG=$(mktemp)
    if ! xcrun notarytool submit "${RELEASE_DIR}/${DMG_NAME}" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait \
        2>&1 | tee "$NOTARY_LOG"; then
        echo ""
        echo "Notarization submission failed."
        rm -f "$NOTARY_LOG"
        exit 1
    fi

    if ! grep -q "status: Accepted" "$NOTARY_LOG"; then
        echo ""
        echo "Notarization was not accepted."
        SUBMISSION_ID=$(grep -m1 "  id:" "$NOTARY_LOG" | awk '{print $2}')
        if [ -n "$SUBMISSION_ID" ]; then
            echo "Fetching notarization log for submission ${SUBMISSION_ID}..."
            xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
        fi
        rm -f "$NOTARY_LOG"
        exit 1
    fi
    rm -f "$NOTARY_LOG"
    echo "Notarization accepted."

    echo "Stapling ticket..."
    xcrun stapler staple "${RELEASE_DIR}/${DMG_NAME}"

    echo "Verifying Gatekeeper assessment..."
    if ! spctl -a -t open --context context:primary-signature -v "${RELEASE_DIR}/${DMG_NAME}"; then
        echo ""
        echo "Gatekeeper assessment failed."
        exit 1
    fi

    echo "DMG signed, notarized, and stapled."
    echo ""
fi

if [ "$NO_UPLOAD" = true ]; then
    echo "--no-upload specified — skipping GitHub release."
    echo ""
    echo "=== Done ==="
    exit 0
fi

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
