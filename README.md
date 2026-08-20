# LightApp — a Lightning wallet that doesn't hide your node

An Android wallet (Kotlin + Jetpack Compose) built on Blockstream
**[Greenlight](https://blockstream.github.io/greenlight/)**. Unlike custodial or
LSP-abstracted wallets, LightApp gives you a **full Core Lightning node** whose
keys live only on your phone: Greenlight runs the node in the cloud, but every
signature is produced on-device by an in-app signer. You get the whole RPC
surface — channels, liquidity, invoices, `xpay`/`pay`/`renepay`, on-chain — in
a clean UI, instead of a locked-down "balance and a send button".

> ⚠️ **Alpha software, real money.** This wallet targets **mainnet** and has
> **not** been through a third-party security audit. It has had an internal
> review (see [Security](#security)), but you use it at your own risk. Start
> with small amounts. Back up your recovery phrase. Do not put in more than you
> are willing to lose.

## Features

<table>
  <tr>
    <td align="center" width="33%">
      <img src="docs/screenshots/welcome.png" width="260" alt="Welcome screen"><br>
      <b>Onboarding</b><br>
      <sub>Create a 24-word BIP39 wallet or restore from seed — pasting the
      whole phrase fills every word box. Open source, and the app says so up
      front: the welcome screen links straight to this repo.</sub>
    </td>
    <td align="center" width="33%">
      <img src="docs/screenshots/cert-upload.png" width="260" alt="Greenlight credentials screen"><br>
      <b>Greenlight credentials</b><br>
      <sub>Upload the developer certificate pair from the Greenlight console
      (linked in-app). They authorize node registration and scheduling, and
      are stored encrypted via the Android Keystore.</sub>
    </td>
    <td align="center" width="33%">
      <img src="docs/screenshots/main.png" width="260" alt="Main tab"><br>
      <b>Main</b><br>
      <sub>On-chain and Lightning balances, live node status, node ID, and
      recent activity — payments, invoices, and transactions, each tappable
      through to its detail. Auto-refreshes every 30&nbsp;s.</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/screenshots/invoices-payments.png" width="260" alt="Invoices — payments"><br>
      <b>Invoices &amp; payments</b><br>
      <sub>Created invoices (paid / unpaid / expired) and sent payments,
      labeled by their invoice description. Payments run asynchronously — a
      routing payment shows as in-flight while the app stays fully
      usable.</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/transactions.png" width="260" alt="Transactions tab"><br>
      <b>Transactions</b><br>
      <sub>On-chain history with inline detail: TXID linking out to
      <a href="https://mempool.space">mempool.space</a>, confirmation count,
      and the node-tracked inputs and outputs of each transaction.</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/channels.png" width="260" alt="Channels tab"><br>
      <b>Channels</b><br>
      <sub>Total outbound / inbound liquidity with per-channel balance bars
      and state. Channel detail exposes reserves, fees, and HTLC limits;
      close from the app.</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/screenshots/open-channel-sheet.png" width="260" alt="Open channel sheet"><br>
      <b>Open channel</b><br>
      <sub>Peer connect string, amount, min conf, feerate presets and the
      announce toggle — <code>connect</code> then <code>fundchannel</code>
      in one tap.</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/utxos.png" width="260" alt="UTXOs tab"><br>
      <b>UTXOs</b><br>
      <sub>Raw coin control view: every output your node tracks, filtered by
      confirmed / unconfirmed / spent / immature, with its address and
      outpoint linking to the explorer.</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/receive-sheet.png" width="260" alt="Receive sheet"><br>
      <b>Receive</b><br>
      <sub>Fresh bech32 address as QR + text (<code>newaddr</code>), with
      one-tap regeneration — a new address after each use.</sub>
    </td>
  </tr>
  <tr>
    <td align="center">
      <img src="docs/screenshots/pay-sheet.png" width="260" alt="Pay sheet"><br>
      <b>Pay</b><br>
      <sub>Paste a bolt11 invoice or bolt12 offer, get a decode preview, and
      pay via <b>xpay</b> (multi-part) with the full argument set: maxfee,
      retry_for, maxdelay, partial_msat, askrene layers. Runs in the
      background while you keep using the app.</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/create-invoice.png" width="260" alt="Create invoice sheet"><br>
      <b>Create invoice</b><br>
      <sub>Every <code>invoice</code> argument: fixed or any amount,
      description, expiry, label, CLTV, on-chain fallback address, custom or
      auto preimage, and <code>exposeprivatechannels</code>
      (bool or explicit SCIDs).</sub>
    </td>
    <td align="center">
      <img src="docs/screenshots/send-chain-sheet.png" width="260" alt="Send on-chain sheet"><br>
      <b>Send on-chain</b><br>
      <sub><code>withdraw</code> with available balance shown, a Send-max
      option, and slow / normal / urgent feerate presets.</sub>
    </td>
  </tr>
  <tr>
    <td align="center" colspan="3">
      <img src="docs/screenshots/settings.png" width="260" alt="Settings tab"><br>
      <b>Settings</b><br>
      <sub>Display unit (sat / msat / BTC), reveal the recovery phrase,
      export the Greenlight certificate and key, a link to this repo, and a
      danger zone that wipes seed and credentials from the device.</sub>
    </td>
  </tr>
</table>

## Architecture

```
core/       Rust crate `lightcore` — wraps Blockstream's gl-client 0.6 and
            exposes a mobile-friendly API over UniFFI. Holds the signer, does
            seed derivation, and maps every CLN RPC to a Kotlin-friendly model.
app/        Android app (package app.light.wallet), Jetpack Compose UI.
scripts/    bootstrap.sh (one-shot host setup + build) and build-rust.sh
            (cross-compiles the .so + regenerates the UniFFI Kotlin bindings).
design/     Snapshot of the reference design (see Design credit below).
```

Data flow: the UI reads shared `StateFlow`s on `WalletRepository`; each Core
Lightning RPC has exactly one flow, so one refresh updates every screen that
shows the data. The Main tab auto-refreshes every 30 s; other tabs refresh on
entry and via pull-to-refresh. The node + signer are released when the app is
backgrounded (unless a payment is dispatching) and re-scheduled on foreground.

## Building

Prerequisites: **Android Studio** (any recent version — it bundles a JDK) and
**Rust** via [rustup](https://rustup.rs). Everything else installs itself.

```bash
./scripts/bootstrap.sh          # install NDK/cargo-ndk/protoc if missing,
                                # build everything, launch an emulator
./scripts/bootstrap.sh --build  # same, but stop after building the APK
```

After the first run (or if you already have the NDK + cargo-ndk + protoc), just
**open the folder in Android Studio and press Run** — the Gradle build has a
`:app:buildRustCore` task that compiles
`app/src/main/jniLibs/arm64-v8a/liblightcore.so` and regenerates the UniFFI
bindings under `app/src/main/java/app/light/wallet/core/` automatically. Both of
those are generated and **git-ignored**.

Pinned toolchain (nothing to configure): Gradle 9.2.1 (committed wrapper) · AGP
8.13 · Kotlin 2.2.20 · NDK `27.2.12479018` · `gl-client 0.6.0`. Only `arm64-v8a`
is built (modern phones + the emulator on Apple Silicon) — add targets to
`scripts/build-rust.sh` and `abiFilters` for more.

You will also need Greenlight developer credentials (a certificate + key) from
the [Greenlight console](https://blockstream.github.io/greenlight/) to register
or recover a node.

### Release signing

Release builds are **not** signed with the public Android debug key. To produce
a signed release, create `app/keystore.properties` (git-ignored):

```properties
storeFile=/absolute/path/to/your-release.jks
storePassword=…
keyAlias=…
keyPassword=…
```

Without it, `assembleRelease` produces an **unsigned** APK (sign it yourself
before installing). Debug builds are unaffected.

## Security

The wallet's job is to keep your seed on your device and your funds yours.

- **Seed never leaves the device.** Greenlight only ever sees signatures from
  the in-app signer — that is the entire point of Greenlight.
- **At rest:** mnemonic + device credentials + Greenlight cert/key are AES-GCM
  encrypted with an Android Keystore key that is StrongBox-backed where the
  device provides it and **unusable while the device is locked**;
  `allowBackup=false`; secrets are git-ignored.
- **On screen:** seed reveal screens set `FLAG_SECURE` (no screenshots, no
  Recents thumbnail, no screen recording) and are hidden from accessibility
  services.
- **Clipboard:** copying the seed or a private key marks the clip sensitive and
  auto-clears it after 60 s.
- **In memory:** the seed is zeroized in the Rust core after use.
- **Logging:** the Rust/gl-client logs (which contain node/payment metadata) are
  emitted **only on debug builds**.

Known limitations / not yet done: no biometric prompt gating reveal & send (the
key is device-lock gated instead); if the signer dies mid-session the UI can
still look connected and a subsequent payment may hang (no double-spend — it
just won't complete until you reconnect); balances can read low transiently
while a channel is opening/closing. This code has **not** had an external audit.

**Responsible disclosure:** please report security issues privately to the
maintainer rather than opening a public issue.

## Design credit

The visual language is adapted from **"Crypto Wallet App UI Template" by
[DSCODE](https://www.figma.com/community/file/1540673463269508643)** (Figma
Community). `design/lightning-wallet.dc.html` is a local snapshot of the
LightApp-specific design. Fonts (Manrope, Space Grotesk, JetBrains Mono) are
bundled under `app/src/main/res/font/`.

## Contributing

Issues and PRs welcome. Keep the security properties above intact — anything
touching the seed, the Keystore, clipboard, `FLAG_SECURE`, or the payment state
machine deserves extra scrutiny in review.

## License

[MIT](LICENSE). The visual design is adapted from the DSCODE template credited
above, which carries its own Figma Community terms.
