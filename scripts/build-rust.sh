#!/usr/bin/env bash
# Build the Rust core for Android and regenerate the Kotlin bindings.
# Normally invoked by Gradle (:app:buildRustCore), which passes ANDROID_NDK_HOME.
#
# Prerequisites (scripts/bootstrap.sh installs all of these):
#   rustup target add aarch64-linux-android
#   cargo install cargo-ndk
#   brew install protobuf
#   NDK r27+ (auto-detected below when ANDROID_NDK_HOME is unset)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/core"
JNILIBS="$ROOT/app/src/main/jniLibs"
KOTLIN_OUT="$ROOT/app/src/main/java"

if [ -z "${ANDROID_NDK_HOME:-}" ]; then
  NDK_DIR="${ANDROID_HOME:-$HOME/Library/Android/sdk}/ndk"
  [ -d "$NDK_DIR" ] || { echo "ERROR: no NDK found; run scripts/bootstrap.sh" >&2; exit 1; }
  ANDROID_NDK_HOME="$NDK_DIR/$(ls "$NDK_DIR" | sort -V | tail -1)"
  export ANDROID_NDK_HOME
  echo "==> Using NDK: $ANDROID_NDK_HOME"
fi

cd "$CORE"

echo "==> Building liblightcore.so for arm64-v8a"
cargo ndk -t arm64-v8a -o "$JNILIBS" build --release

# liblightcore.so links against the NDK's shared C++ runtime (pulled in by a
# C++ dependency of gl-client); the emulator/device doesn't ship it, so it must
# travel inside the APK next to our library.
echo "==> Bundling libc++_shared.so"
LIBCXX="$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -path "*aarch64-linux-android/libc++_shared.so" | head -1)"
[ -n "$LIBCXX" ] || { echo "ERROR: libc++_shared.so not found in NDK" >&2; exit 1; }
cp "$LIBCXX" "$JNILIBS/arm64-v8a/"

echo "==> Generating Kotlin bindings"
cargo run --features cli --bin uniffi-bindgen -- \
    generate --library "$JNILIBS/arm64-v8a/liblightcore.so" \
    --language kotlin \
    --out-dir "$KOTLIN_OUT" \
    --no-format

echo "==> Done. Bindings at app/src/main/java/app/light/wallet/core/"
