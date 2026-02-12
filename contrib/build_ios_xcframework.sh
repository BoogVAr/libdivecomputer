#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT_DIR/native/ios"
BUILD_DIR="$ROOT_DIR/build/ios"
MIN_IOS_VERSION="12.0"

LIB_NAME="libdivecomputer"

function host_triplet() {
  local arch="$1"
  case "$arch" in
    arm64) echo "arm-apple-darwin";;
    x86_64) echo "x86_64-apple-darwin";;
    *) echo "arm-apple-darwin";;
  esac
}

function build_arch() {
  local sdk="$1"
  local arch="$2"
  local build_subdir="$BUILD_DIR/${sdk}-${arch}"
  local prefix="$build_subdir/install"

  rm -rf "$build_subdir"
  mkdir -p "$build_subdir"

  pushd "$build_subdir" >/dev/null

  export CC="$(xcrun --sdk ${sdk} --find clang)"
  export CFLAGS="-arch ${arch} -isysroot $(xcrun --sdk ${sdk} --show-sdk-path) -miphoneos-version-min=${MIN_IOS_VERSION}"
  export LDFLAGS="-arch ${arch} -isysroot $(xcrun --sdk ${sdk} --show-sdk-path) -miphoneos-version-min=${MIN_IOS_VERSION}"

  "$ROOT_DIR/configure" \
    --host="$(host_triplet ${arch})" \
    --prefix="$prefix" \
    --disable-shared \
    --enable-static \
    --enable-examples=no \
    --enable-doc=no \
    --without-libusb \
    --without-hidapi \
    --without-bluez

  make -j$(sysctl -n hw.ncpu)
  make install

  popd >/dev/null
}

build_arch iphoneos arm64
build_arch iphonesimulator arm64
build_arch iphonesimulator x86_64

# Create xcframework
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# Create a fat simulator library to avoid duplicate ios-arm64 identifiers.
SIM_FAT_DIR="$BUILD_DIR/iphonesimulator-universal"
SIM_FAT_LIB="$SIM_FAT_DIR/install/lib/${LIB_NAME}.a"
mkdir -p "$(dirname "$SIM_FAT_LIB")"
lipo -create \
  "$BUILD_DIR/iphonesimulator-arm64/install/lib/${LIB_NAME}.a" \
  "$BUILD_DIR/iphonesimulator-x86_64/install/lib/${LIB_NAME}.a" \
  -output "$SIM_FAT_LIB"

xcodebuild -create-xcframework \
  -library "$BUILD_DIR/iphoneos-arm64/install/lib/${LIB_NAME}.a" \
  -headers "$BUILD_DIR/iphoneos-arm64/install/include" \
  -library "$SIM_FAT_LIB" \
  -headers "$BUILD_DIR/iphonesimulator-arm64/install/include" \
  -output "$OUT_DIR/${LIB_NAME}.xcframework"

echo "XCFramework created at $OUT_DIR/${LIB_NAME}.xcframework"
