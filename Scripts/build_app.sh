#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Teleport"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
ICON_SOURCE="$ROOT_DIR/icon.icon"
ICON_NAME="AppIcon"
CODE_SIGN_IDENTITY="${TELEPORT_CODESIGN_IDENTITY:--}"
CERT_NAME="Teleport Development"
APP_VERSION="${TELEPORT_VERSION:-1.0.0}"
APP_BUILD="${TELEPORT_BUILD:-1}"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

# Use a stable signing identity so macOS preserves Accessibility permissions across rebuilds.
# Ad-hoc signing ("-") changes the CDHash every build, which invalidates TCC entries.
ensure_signing_identity() {
    if [ "$CODE_SIGN_IDENTITY" != "-" ]; then
        return
    fi

    # Check if our self-signed certificate already exists
    if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
        CODE_SIGN_IDENTITY="$CERT_NAME"
        return
    fi

    echo "Creating self-signed certificate \"$CERT_NAME\" for stable code signing..."
    local TMPDIR_CERT
    TMPDIR_CERT=$(mktemp -d /tmp/teleport-cert.XXXXXX)

    # Generate certificate with code signing extensions
    openssl req -x509 -newkey rsa:2048 \
        -keyout "$TMPDIR_CERT/key.pem" \
        -out "$TMPDIR_CERT/cert.pem" \
        -days 3650 -nodes \
        -subj "/CN=$CERT_NAME" \
        -addext "keyUsage=digitalSignature" \
        -addext "extendedKeyUsage=codeSigning" 2>/dev/null

    # Export as PKCS12 (-legacy required for macOS Security framework compatibility)
    openssl pkcs12 -export \
        -out "$TMPDIR_CERT/cert.p12" \
        -inkey "$TMPDIR_CERT/key.pem" \
        -in "$TMPDIR_CERT/cert.pem" \
        -passout pass:teleport -legacy 2>/dev/null

    # Import identity into login keychain
    security import "$TMPDIR_CERT/cert.p12" \
        -k ~/Library/Keychains/login.keychain-db \
        -P "teleport" \
        -T /usr/bin/codesign 2>/dev/null

    # Trust the certificate for code signing
    security add-trusted-cert -r trustRoot -p codeSign \
        -k ~/Library/Keychains/login.keychain-db \
        "$TMPDIR_CERT/cert.pem" 2>/dev/null

    rm -rf "$TMPDIR_CERT"

    if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
        CODE_SIGN_IDENTITY="$CERT_NAME"
        echo "Certificate \"$CERT_NAME\" created successfully."
    else
        echo "Warning: Could not create signing certificate. Falling back to ad-hoc signing."
        echo "  Accessibility permissions will need to be re-granted after each build."
    fi
}

build_icns() {
    local ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool"
    local RENDERED_PNG
    RENDERED_PNG="$(mktemp /tmp/teleport-icon-XXXXXX.png)"
    local ICONSET_DIR
    ICONSET_DIR="$(mktemp -d /tmp/teleport-iconset-XXXXXX.iconset)"

    # Render icon.icon via ictool (Icon Composer CLI)
    "$ICTOOL" "$ICON_SOURCE" --export-preview macOS Light 1024 1024 1 "$RENDERED_PNG"

    # Generate iconset sizes
    local size
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$RENDERED_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$RENDERED_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
    done

    iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/$ICON_NAME.icns"
    rm -f "$RENDERED_PNG"
    rm -rf "$ICONSET_DIR"
}

set_plist_value() {
    local key="$1"
    local type="$2"
    local value="$3"

    if "$PLIST_BUDDY" -c "Print :$key" "$APP_DIR/Contents/Info.plist" >/dev/null 2>&1; then
        "$PLIST_BUDDY" -c "Set :$key $value" "$APP_DIR/Contents/Info.plist"
    else
        "$PLIST_BUDDY" -c "Add :$key $type $value" "$APP_DIR/Contents/Info.plist"
    fi
}

configure_info_plist() {
    cp "$ROOT_DIR/AppResources/Info.plist" "$APP_DIR/Contents/Info.plist"

    set_plist_value "CFBundleShortVersionString" "string" "$APP_VERSION"
    set_plist_value "CFBundleVersion" "string" "$APP_BUILD"
}

ensure_signing_identity

cd "$ROOT_DIR"
env \
    CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
    SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
    swift build -c release --product "$APP_NAME"

BUILD_BIN_DIR="$(
    env \
        CLANG_MODULE_CACHE_PATH=/tmp/clang-module-cache \
        SWIFTPM_MODULECACHE_OVERRIDE=/tmp/swiftpm-module-cache \
        swift build -c release --product "$APP_NAME" --show-bin-path
)"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
rm -f "$APP_DIR/Contents/MacOS/$APP_NAME"
rm -f "$APP_DIR/Contents/Info.plist"
rm -f "$APP_DIR/Contents/Resources/$ICON_NAME.icns"
rm -rf "$APP_DIR/Contents/_CodeSignature"

cp "$BUILD_BIN_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy SPM resource bundle if present
RESOURCE_BUNDLE="$BUILD_BIN_DIR/Teleport_Teleport.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
    rm -rf "$APP_DIR/Contents/Resources/Teleport_Teleport.bundle"
    cp -R "$RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
fi

configure_info_plist
build_icns

# Strip resource forks and Finder metadata that would break code signing.
xattr -cr "$APP_DIR"

# Use an explicit designated requirement based on bundle identifier only,
# so macOS TCC preserves Accessibility permissions across rebuilds.
BUNDLE_ID="$("$PLIST_BUDDY" -c "Print :CFBundleIdentifier" "$APP_DIR/Contents/Info.plist")"
codesign --force --deep -s "$CODE_SIGN_IDENTITY" \
    -r="designated => identifier \"$BUNDLE_ID\"" \
    "$APP_DIR"

touch "$APP_DIR"

echo "Built app bundle at: $APP_DIR"
