#!/bin/bash
set -e

# Local IPA build script for EeveeSpotify
# This script matches the GitHub Actions workflow but runs locally

SPOTIFY_IPA="${1:-Decrypted IPA/com.spotify.client-9.1.6-Decrypted.ipa}"
VERSION="6.4.9"
OUTPUT_DIR="Outputs/IPAS"

# Determine package scheme (rootful=arm, rootless=arm64)
PACKAGE_SCHEME="${THEOS_PACKAGE_SCHEME:-rootful}"
if [ "$PACKAGE_SCHEME" = "rootless" ]; then
  ARCH="arm64"
else
  ARCH="arm"
fi

# Extract Spotify version from filename
SPOTIFY_VERSION=$(basename "$SPOTIFY_IPA" | sed -E 's/.*-([0-9.]+)-Decrypted.ipa/\1/')

# Output filenames
BASE_IPA="$OUTPUT_DIR/EeveeSpotify.ipa"
PATCHED_IPA="$OUTPUT_DIR/EeveeSpotify-patched.ipa"

echo "======================================"
echo "Building EeveeSpotify IPA"
echo "======================================"
echo "Spotify version: $SPOTIFY_VERSION"
echo "EeveeSpotify version: $VERSION"
echo "Input: $SPOTIFY_IPA"
echo "======================================"

# Ensure output directory exists
mkdir -p "$OUTPUT_DIR"

# Step 1: Inject tweak with ivinject
echo "Step 1/4: Injecting tweak with ivinject..."
echo "Using package scheme: $PACKAGE_SCHEME ($ARCH)"
ivinject-arm64 \
  "$SPOTIFY_IPA" \
  "$BASE_IPA" \
  -i "packages/com.eevee.spotify_${VERSION}_iphoneos-${ARCH}.deb" \
     "${THEOS}/lib/iphone/rootless/SwiftProtobuf.framework" \
     "/tmp/ees-ipa/OpenSpotifySafariExtension/OpenSpotifySafariExtension.appex" \
  -s - -d --level Optimal \
  -r Watch

echo ""
echo "Step 2/4: Applying ipapatch..."
ipapatch -input "$BASE_IPA" -output "$PATCHED_IPA"

echo ""
echo "Step 3/4: Stripping Watch bundle (if any remains)..."
cd "$OUTPUT_DIR"
rm -rf Payload
unzip -q "$(basename "$PATCHED_IPA")"
if [ -d "Payload/Spotify.app/Watch" ]; then
  echo "  Removing Payload/Spotify.app/Watch"
  rm -rf Payload/Spotify.app/Watch
  # Repackage over the patched IPA
  zip -qry "$(basename "$PATCHED_IPA")" Payload
else
  echo "  Watch bundle already removed"
fi
rm -rf Payload
cd - > /dev/null

echo ""
echo "Step 4/4: Cleanup intermediate files..."
# Keep both base and patched IPAs (no intermediate cleanup needed)

echo ""
echo "======================================"
echo "✅ Build complete!"
echo "======================================"
echo "Base IPA:    $BASE_IPA"
echo "Patched IPA: $PATCHED_IPA"
ls -lh "$BASE_IPA" "$PATCHED_IPA"
echo ""
echo "Install with AltStore/Sideloadly or TrollStore"
