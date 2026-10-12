#!/bin/bash
# Copy Homebrew HackRF/libusb/LAME into the app and re-sign them with the app identity.
# Hardened runtime rejects the Homebrew copies because their Team ID does not match.
set -euo pipefail

APP="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
FW="${APP}/Contents/Frameworks"
mkdir -p "$FW"

locate() {
    local formula="$1"
    local leaf="$2"
    local candidate
    for candidate in "/opt/homebrew/opt/${formula}/lib/${leaf}" "/usr/local/opt/${formula}/lib/${leaf}"; do
        if [[ -e "$candidate" ]]; then
            python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$candidate"
            return 0
        fi
    done
    echo "embed-libraries: missing ${formula} (${leaf})" >&2
    exit 1
}

install_copy() {
    local src="$1"
    local name="$2"
    cp -f "$src" "${FW}/${name}"
    chmod u+w "${FW}/${name}"
    install_name_tool -id "@rpath/${name}" "${FW}/${name}"
}

HACKRF="$(locate hackrf libhackrf.0.dylib)"
LAME="$(locate lame libmp3lame.0.dylib)"
USB="$(locate libusb libusb-1.0.0.dylib)"

install_copy "$HACKRF" "libhackrf.0.dylib"
install_copy "$LAME" "libmp3lame.0.dylib"
install_copy "$USB" "libusb-1.0.0.dylib"

rewrite() {
    local bin="$1"
    [[ -f "$bin" ]] || return 0
    local own
    own="$(otool -D "$bin" 2>/dev/null | awk 'NR==2 { print; exit }')"
    otool -L "$bin" | awk 'NR>1 { print $1 }' | while read -r dep; do
        [[ -n "$dep" && "$dep" != "$own" ]] || continue
        case "$dep" in
            *libhackrf*.dylib)
                install_name_tool -change "$dep" "@rpath/libhackrf.0.dylib" "$bin"
                ;;
            *libmp3lame*.dylib)
                install_name_tool -change "$dep" "@rpath/libmp3lame.0.dylib" "$bin"
                ;;
            *libusb*.dylib)
                install_name_tool -change "$dep" "@loader_path/libusb-1.0.0.dylib" "$bin"
                ;;
        esac
    done
}

rewrite "${FW}/libhackrf.0.dylib"
rewrite "${FW}/libmp3lame.0.dylib"
rewrite "${FW}/libusb-1.0.0.dylib"
rewrite "${APP}/Contents/MacOS/HackRFSWRadio"
rewrite "${APP}/Contents/MacOS/HackRFSWRadio.debug.dylib"

# App Store symbol upload matches every embedded binary UUID to a dSYM.
DSYM_DIR="${DWARF_DSYM_FOLDER_PATH:-${BUILT_PRODUCTS_DIR}}"
mkdir -p "$DSYM_DIR"
for lib in "${FW}/libhackrf.0.dylib" "${FW}/libmp3lame.0.dylib" "${FW}/libusb-1.0.0.dylib"; do
    name="$(basename "$lib")"
    dsymutil "$lib" -o "${DSYM_DIR}/${name}.dSYM" || true
    if [[ -n "${BUILT_PRODUCTS_DIR:-}" && "$BUILT_PRODUCTS_DIR" != "$DSYM_DIR" ]]; then
        rm -rf "${BUILT_PRODUCTS_DIR}/${name}.dSYM"
        cp -R "${DSYM_DIR}/${name}.dSYM" "${BUILT_PRODUCTS_DIR}/${name}.dSYM"
    fi
done

SIGN_ID="${EXPANDED_CODE_SIGN_IDENTITY:--}"
if [[ -z "$SIGN_ID" ]]; then
    SIGN_ID="-"
fi
for lib in "${FW}"/*.dylib; do
    codesign --force --sign "$SIGN_ID" --timestamp=none "$lib"
done
