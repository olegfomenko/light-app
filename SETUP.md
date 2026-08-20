# LightApp — Development Environment Setup

> **TL;DR:** install Android Studio + rustup, then run `./scripts/bootstrap.sh`.
> It installs everything else (NDK, cargo-ndk, protoc, SDK bits) and builds the
> app. The manual notes below are kept for reference/debugging.

Target: **native Android now** (Kotlin + Jetpack Compose, Rust core via UniFFI wrapping Blockstream's `gl-client`), **native iOS later** (Swift + SwiftUI, same Rust core).

Machine: MacBook Pro, **Apple Silicon (arm64)** — commands below assume that.

> Note: you already have Rust (`~/.rustup`, `~/.cargo`) and a Gradle/JetBrains setup on this machine, so several steps are just "add targets", not fresh installs.

---

## 1. Base tooling

| What | How | Why |
|---|---|---|
| Xcode Command Line Tools | `xcode-select --install` (skip if already prompted before) | clang, git, headers — required by Rust builds |
| Homebrew | already common on dev Macs; if missing: [brew.sh](https://brew.sh) | package manager for the rest |
| Protobuf compiler | `brew install protobuf` | `gl-client` uses tonic/prost gRPC; its build needs `protoc` |
| CMake (optional) | `brew install cmake` | some native deps (e.g. secp256k1 sys crates) build faster/cleaner with it present |

## 2. Rust side (you already have rustup)

```sh
# Update toolchain
rustup update stable

# Android targets (arm64 covers real devices AND the emulator on your M-series Mac)
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android

# Build helper that wires the Android NDK into cargo
cargo install cargo-ndk
```

Nothing to install globally for UniFFI — `uniffi` is just a dependency in the wrapper crate's `Cargo.toml`, and the bindgen runs via `cargo run --bin uniffi-bindgen`.

## 3. Android side

1. **Android Studio** — download from [developer.android.com/studio](https://developer.android.com/studio) (Apple Silicon build). Bundles its own JDK, SDK manager, and emulator.
2. In **Settings → SDK Manager**, install:
   - **Android SDK Platform 35** (or newest stable offered)
   - **Android SDK Platform-Tools** (adb)
   - **Android Emulator** + an **arm64-v8a system image** (API 35)
   - **NDK (Side by side)** — pick **r27 or newer** (required for Android 15's 16 KB page-size rule; older NDKs will bite you later)
3. Environment variables (add to `~/.zshrc`):

```sh
export ANDROID_HOME="$HOME/Library/Android/sdk"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/<version you installed>"
export PATH="$ANDROID_HOME/platform-tools:$PATH"
```

`cargo ndk` auto-detects the NDK from these.

## 4. Greenlight access

- Sign up at the **Greenlight Developer Console** — [blockstream.com/greenlight](https://blockstream.com/greenlight) / [docs](https://blockstream.github.io/greenlight/getting-started/) — to obtain your **developer/partner certificate + key**. `gl-client` needs these to register and schedule nodes (mTLS).
- Keep the cert/key out of git; load via env or a local untracked file.
- For app-level testing you can run against **testnet/regtest** first — see [Greenlight: testing your app](https://blockstream.github.io/greenlight/tutorials/testing/).

## 5. Accounts (when publishing)

- **Google Play Console** — one-time **$25** — needed only when you're ready to publish.
- **Apple Developer Program** — **$99/year** — needed later for iOS device testing/TestFlight/App Store.

## 6. iOS — later (nothing to do now)

When you start iOS:

```sh
# Full Xcode from the Mac App Store (the CLI tools alone are not enough)
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
```

The same Rust wrapper crate then builds into an **XCFramework**, and UniFFI generates the Swift bindings. No CocoaPods needed for a pure SwiftUI app (use Swift Package Manager).

---

## Quick sanity check after installing

```sh
protoc --version                 # libprotoc 2x.x
rustup target list --installed   # shows the android targets
cargo ndk --version
adb --version
```

Then a first milestone: build a "hello" Rust crate into an `.aar` with `cargo ndk -t arm64-v8a -o app/src/main/jniLibs build`, call it from Kotlin — before pulling in `gl-client`.
