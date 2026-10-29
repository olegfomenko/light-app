#!/usr/bin/env bash
# Build the Rust core for iOS and regenerate the Swift bindings + XCFramework.
# Invoked by the Xcode "Build Rust core" run-script phase; safe to run by hand.
#
# Prerequisites:
#   rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#   brew install protobuf
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
OUT="$ROOT/ios/LightCore"
GEN="$OUT/Generated"

export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
# Xcode run-script phases export iOS SDK vars that break the *host* build of
# uniffi-bindgen and confuse cargo; scrub them and let cargo pick per-target.
unset SDKROOT IPHONEOS_DEPLOYMENT_TARGET LIBRARY_PATH

cd "$CORE"

echo "==> Building lightcore for iOS (device + simulator)"
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim

echo "==> Generating Swift bindings"
mkdir -p "$GEN"
cargo run --features cli --bin uniffi-bindgen -- \
    generate --library target/aarch64-apple-ios/release/liblightcore.a \
    --language swift --out-dir "$GEN" --no-format 2>/dev/null || \
cargo run --features cli --bin uniffi-bindgen -- \
    generate --library "$ROOT/android/src/main/jniLibs/arm64-v8a/liblightcore.so" \
    --language swift --out-dir "$GEN" --no-format

# Skip repackaging when the existing xcframework is newer than both static
# libs — and never delete-in-place: Xcode's framework-processing task can run
# CONCURRENTLY with this script phase, so the swap must be atomic (mv).
DEV_A="$CORE/target/aarch64-apple-ios/release/liblightcore.a"
SIM_A="$CORE/target/aarch64-apple-ios-sim/release/liblightcore.a"
XCF="$OUT/LightCore.xcframework"
if [ -d "$XCF" ] && [ "$XCF" -nt "$DEV_A" ] && [ "$XCF" -nt "$SIM_A" ]; then
  echo "==> LightCore.xcframework up to date"
else
  echo "==> Packaging LightCore.xcframework"
  STAGE="$(mktemp -d)"
  mkdir -p "$STAGE/headers"
  cp "$GEN/lightcoreFFI.h" "$STAGE/headers/"
  # XCFramework wants the canonical module map name.
  cp "$GEN/lightcoreFFI.modulemap" "$STAGE/headers/module.modulemap"
  xcodebuild -create-xcframework \
      -library "$DEV_A" -headers "$STAGE/headers" \
      -library "$SIM_A" -headers "$STAGE/headers" \
      -output "$STAGE/LightCore.xcframework"
  rm -rf "$XCF"
  mv "$STAGE/LightCore.xcframework" "$XCF"
  rm -rf "$STAGE"
fi

echo "==> Done. ios/LightCore/LightCore.xcframework + Generated/lightcore.swift"
