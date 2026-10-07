#!/bin/bash
# Builds libmp3lame.xcframework (universal macOS dynamic library) from the
# vendored LAME 3.100 source tarball.
#
# LAME is licensed under the LGPL v2. We link it dynamically and keep the
# source tarball in Vendor/ so the relink/source requirements are satisfied.
# See THIRD_PARTY_LICENSES.md.
#
# Output: Frameworks/libmp3lame.xcframework

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARBALL="$ROOT/Vendor/lame-3.100.tar.gz"
BUILD_DIR="$ROOT/Vendor/lame-build"
OUT="$ROOT/Frameworks/libmp3lame.xcframework"
MACOS_MIN="14.0"

if [[ ! -f "$TARBALL" ]]; then
    echo "error: $TARBALL not found" >&2
    exit 1
fi

rm -rf "$BUILD_DIR" "$OUT"
mkdir -p "$BUILD_DIR"

build_arch() {
    local arch="$1"
    local host="$2"
    local src="$BUILD_DIR/src-$arch"

    mkdir -p "$src"
    tar -xzf "$TARBALL" -C "$src" --strip-components=1

    # lame 3.100 exports lame_init_old in its .sym file but modern clang does
    # not emit the symbol, which fails the link. Remove it (standard fix).
    sed -i '' '/lame_init_old/d' "$src/include/libmp3lame.sym"

    pushd "$src" > /dev/null
    CC="clang" \
    CFLAGS="-arch $arch -mmacosx-version-min=$MACOS_MIN -Os" \
    LDFLAGS="-arch $arch -mmacosx-version-min=$MACOS_MIN" \
    ./configure \
        --host="$host-apple-darwin" \
        --disable-dependency-tracking \
        --disable-frontend \
        --disable-static \
        --enable-shared \
        --enable-nasm=no \
        > "$BUILD_DIR/configure-$arch.log" 2>&1
    make -j"$(sysctl -n hw.ncpu)" > "$BUILD_DIR/make-$arch.log" 2>&1
    popd > /dev/null
}

echo "Building arm64..."
build_arch arm64 aarch64
echo "Building x86_64..."
build_arch x86_64 x86_64

DYLIB_ARM="$BUILD_DIR/src-arm64/libmp3lame/.libs/libmp3lame.0.dylib"
DYLIB_X86="$BUILD_DIR/src-x86_64/libmp3lame/.libs/libmp3lame.0.dylib"

echo "Creating universal dylib..."
UNIVERSAL="$BUILD_DIR/libmp3lame.dylib"
lipo -create "$DYLIB_ARM" "$DYLIB_X86" -output "$UNIVERSAL"
install_name_tool -id "@rpath/libmp3lame.dylib" "$UNIVERSAL"

echo "Staging headers..."
HEADERS="$BUILD_DIR/headers"
mkdir -p "$HEADERS/lame"
cp "$BUILD_DIR/src-arm64/include/lame.h" "$HEADERS/lame/lame.h"
cat > "$HEADERS/module.modulemap" <<'EOF'
module CLAME {
    header "lame/lame.h"
    export *
}
EOF

echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "$UNIVERSAL" \
    -headers "$HEADERS" \
    -output "$OUT"

echo "Done: $OUT"
lipo -info "$UNIVERSAL"
