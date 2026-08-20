#!/usr/bin/env bash
# One-shot setup + build + run for LightApp on macOS.
#
#   ./scripts/bootstrap.sh          # configure, build rust + apk, run in emulator
#   ./scripts/bootstrap.sh --build  # stop after building the APK (no emulator)
#
# Safe to re-run; every step is idempotent. After the first successful run you
# can simply open the project in Android Studio and press Run — the Gradle
# build compiles the Rust core automatically.
set -euo pipefail

# Must match ndkVersion in app/build.gradle.kts.
NDK_VERSION="27.2.12479018"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

step() { printf '\n\033[1;33m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- Java / SDK
step "Checking Java"
JBR="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
if [ -z "${JAVA_HOME:-}" ] || ! "${JAVA_HOME}/bin/java" -version >/dev/null 2>&1; then
  if [ -d "$JBR" ]; then
    export JAVA_HOME="$JBR"
    echo "Using Android Studio's bundled JDK: $JAVA_HOME"
  elif command -v java >/dev/null 2>&1; then
    echo "Using system java: $(java -version 2>&1 | head -1)"
  else
    die "No JDK found. Install Android Studio first (it bundles one)."
  fi
fi

step "Checking Android SDK"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Library/Android/sdk}"
[ -d "$ANDROID_HOME" ] || die "Android SDK not found at $ANDROID_HOME. Open Android Studio once and install the SDK."
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# sdkmanager gives us headless installs of NDK/platform-tools. If it's not
# there yet, fetch the official command-line tools once.
if ! command -v sdkmanager >/dev/null 2>&1; then
  step "Installing Android command-line tools (one-time)"
  TMP="$(mktemp -d)"
  curl -sSL -o "$TMP/tools.zip" \
    "https://dl.google.com/android/repository/commandlinetools-mac-13114758_latest.zip"
  unzip -q "$TMP/tools.zip" -d "$TMP"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  rm -rf "$ANDROID_HOME/cmdline-tools/latest"
  mv "$TMP/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
  rm -rf "$TMP"
fi

step "Accepting SDK licenses"
yes | sdkmanager --licenses >/dev/null 2>&1 || true

step "Ensuring platform-tools + NDK $NDK_VERSION"
command -v adb >/dev/null 2>&1 || sdkmanager "platform-tools" >/dev/null
[ -d "$ANDROID_HOME/ndk/$NDK_VERSION" ] || sdkmanager "ndk;$NDK_VERSION" >/dev/null
echo "NDK: $ANDROID_HOME/ndk/$NDK_VERSION"

# ---------------------------------------------------------------- Rust side
step "Checking Rust toolchain"
export PATH="$HOME/.cargo/bin:$PATH"
command -v cargo >/dev/null 2>&1 || die "cargo not found — install rustup (https://rustup.rs)."
rustup target list --installed | grep -q aarch64-linux-android || {
  echo "Adding aarch64-linux-android target"
  rustup target add aarch64-linux-android
}
command -v cargo-ndk >/dev/null 2>&1 || {
  echo "Installing cargo-ndk"
  cargo install cargo-ndk
}
command -v protoc >/dev/null 2>&1 || {
  if command -v brew >/dev/null 2>&1; then
    echo "Installing protobuf via Homebrew"
    brew install protobuf
  else
    die "protoc not found and Homebrew unavailable — install protobuf manually."
  fi
}

# ---------------------------------------------------------------- Build
step "Building debug APK (compiles the Rust core too)"
./gradlew :app:assembleDebug

[ "${1:-}" = "--build" ] && { step "Done (build only). APK: app/build/outputs/apk/debug/"; exit 0; }

# ---------------------------------------------------------------- Emulator
step "Looking for a device/emulator"
if ! adb devices | awk 'NR>1 && $2=="device"' | grep -q .; then
  AVD="$(emulator -list-avds 2>/dev/null | head -1 || true)"
  if [ -z "$AVD" ]; then
    step "No AVD found — creating one (downloads an arm64 system image once)"
    IMG="system-images;android-35;google_apis;arm64-v8a"
    sdkmanager "$IMG" >/dev/null
    echo "no" | "$ANDROID_HOME/cmdline-tools/latest/bin/avdmanager" create avd \
      -n lightapp -k "$IMG" -d pixel_7 >/dev/null
    AVD="lightapp"
  fi
  step "Starting emulator: $AVD"
  nohup emulator -avd "$AVD" >/tmp/lightapp-emulator.log 2>&1 &
  adb wait-for-device
  echo -n "Waiting for boot"
  until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do
    echo -n "."; sleep 2
  done
  echo " booted."
fi

step "Installing and launching LightApp"
./gradlew :app:installDebug
adb shell am start -n app.light.wallet/.MainActivity
step "LightApp is running in the emulator 🎉"
