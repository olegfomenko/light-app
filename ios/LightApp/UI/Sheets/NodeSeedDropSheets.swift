//
//  NodeSeedDropSheets.swift
//  LightApp
//
//  Node info (NodeSheet), recovery phrase (SeedSheet) and wallet erase
//  (DropSheet) sheets. Port of the same-named composables in
//  android/src/main/java/app/light/wallet/ui/sheets/SheetHost.kt.
//

import SwiftUI

// ─────────────────────────── Node info ───────────────────────────

@MainActor
struct NodeSheet: View {
    let repository: WalletRepository
    let onClose: () -> Void

    init(repository: WalletRepository, onClose: @escaping () -> Void) {
        self.repository = repository
        self.onClose = onClose
    }

    var body: some View {
        let unit = DisplayUnit.from(stored: repository.displayUnit)

        SheetTitle(text: "Node", onClose: onClose)

        if let info = repository.connState.info {
            KvPanel(rows: [
                ("Node ID", info.id, true),
                ("Alias", info.alias, false),
                ("Network", info.network, false),
                ("Block height", String(info.blockheight), false),
                ("Version", info.version, false),
                ("Peers", String(info.numPeers), false),
                ("Active channels", String(info.numActiveChannels), false),
                ("Fees collected", formatAmountFull(msat: info.feesCollectedMsat, unit: unit), false),
            ])
        } else {
            Text("Node info is available once connected.")
                .font(Tokens.manrope(14))
                .foregroundStyle(Tokens.Dim)
        }
    }
}

// ─────────────────────────── Recovery phrase ───────────────────────────

/// iOS note: there is no API to block screenshots or screen recording of an
/// ordinary view — Android rebuilt this sheet's window with FLAG_SECURE, but
/// the closest iOS equivalent, the app-wide `privacyCover()` (applied by
/// `SheetHost`), only blanks the app-switcher snapshot. A screenshot taken
/// while the seed is revealed WILL contain the words; the warning copy below
/// is the only guard the platform lets us offer.
@MainActor
struct SeedSheet: View {
    let repository: WalletRepository
    let onClose: () -> Void

    @State private var revealed = false
    /// Live mirror of UIScreen.isCaptured: while the screen is being recorded
    /// or mirrored (AirPlay, QuickTime capture), the words stay masked — the
    /// closest iOS gets to FLAG_SECURE for an actively-observed screen.
    @State private var screenCaptured = UIScreen.main.isCaptured
    /// Keychain decrypt of the mnemonic — loaded asynchronously exactly once
    /// per open (`.task` below); nil until it lands. Never read the secret
    /// synchronously in `body`: on Android the equivalent StrongBox read froze
    /// a frame per recomposition, and the same "no secret-store work on the UI
    /// path" rule carries over here.
    @State private var words: [String]? = nil

    init(repository: WalletRepository, onClose: @escaping () -> Void) {
        self.repository = repository
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: "Recovery phrase", onClose: onClose)
                .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                    screenCaptured = UIScreen.main.isCaptured
                }

            if let loaded = words {
                Text("Anyone with these \(loaded.count) words can take your funds. Reveal only in private.")
                    .font(Tokens.manrope(14))
                    .lineSpacing(4)
                    .foregroundStyle(Tokens.Label)
                    .padding(.bottom, 14)

                if screenCaptured {
                    Text("Screen recording or mirroring is active — the seed stays hidden until it stops.")
                        .font(Tokens.manrope(13, .bold))
                        .foregroundStyle(Tokens.Orange)
                        .padding(.vertical, 24)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    SeedGrid(words: loaded, revealed: revealed) { revealed = true }
                }

                OutlinePillButton(text: "Copy seed") {
                    copyToClipboard(label: "Seed", value: loaded.joined(separator: " "), sensitive: true)
                }
                .padding(.top, 14)

                Text("Reveal requires a private moment — a biometric gate lands before the seed is decrypted in a future release.")
                    .font(Tokens.manrope(12.5))
                    .lineSpacing(3)
                    .foregroundStyle(Tokens.Dim)
                    .padding(.top, 12)
            } else {
                Text("Decrypting…")
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Dim)
                    .padding(.bottom, 14)
            }
        }
        .task {
            words = await repository.loadMnemonicWords()
        }
    }
}

// ─────────────────────────── Delete wallet data ───────────────────────────

@MainActor
struct DropSheet: View {
    let repository: WalletRepository
    let onCancel: () -> Void
    let onWiped: () -> Void

    /// Double-tap confirmation: the first tap arms the button, the second
    /// actually wipes.
    @State private var armed = false

    init(
        repository: WalletRepository,
        onCancel: @escaping () -> Void,
        onWiped: @escaping () -> Void
    ) {
        self.repository = repository
        self.onCancel = onCancel
        self.onWiped = onWiped
    }

    var body: some View {
        // No ✕ bubble on this sheet (Android passes no onClose either) — the
        // explicit Cancel pill below is the only benign way out.
        SheetTitle(text: "Delete wallet data")

        Text(
            "This wipes the seed, Greenlight certificates and local caches from this device. "
                + "Your node stays scheduled at Greenlight — recover it anytime with the 24 words."
        )
        .font(Tokens.manrope(14))
        .lineSpacing(5)
        .foregroundStyle(Color(hex: 0xFFF8B4B2))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Tokens.Red.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Tokens.Red.opacity(0.25), lineWidth: 1)
        )

        // Filled red capsule (unique to this sheet — DangerPillButton is the
        // outlined variant, this is the design's solid "you are sure" state).
        Button {
            if !armed {
                armed = true
            } else {
                repository.wipe()
                onWiped()
            }
        } label: {
            Text(armed ? "Tap again to erase" : "Erase wallet data")
                .font(Tokens.manrope(15, .heavy))
                .foregroundStyle(Color(hex: 0xFF2B0705))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Tokens.Red, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.top, 14)

        GhostButton(text: "Cancel", action: onCancel)
            .padding(.top, 10)
    }
}
