//
//  SettingsTab.swift
//  LightApp
//
//  Settings tab: display unit selector, security actions, danger zone.
//  Port of android/src/main/java/app/light/wallet/ui/settings/SettingsTab.kt.
//

import SwiftUI

@MainActor
struct SettingsTab: View {
    let repository: WalletRepository
    let onOpenSheet: (WalletSheet) -> Void
    /// Passed through from AppRoot; the wipe itself happens in the DropWallet
    /// sheet — Settings only opens it (mirrors the unused Android parameter).
    let onWalletWiped: () -> Void

    /// Local mirror of the stored unit, like Android's `remember { mutableStateOf }`.
    @State private var unit: String

    @Environment(\.openURL) private var openURL

    init(
        repository: WalletRepository,
        onOpenSheet: @escaping (WalletSheet) -> Void,
        onWalletWiped: @escaping () -> Void
    ) {
        self.repository = repository
        self.onOpenSheet = onOpenSheet
        self.onWalletWiped = onWalletWiped
        _unit = State(initialValue: repository.displayUnit)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Settings")
                    .font(Tokens.spaceGrotesk(24, .bold))
                    .foregroundStyle(Tokens.Text)
                    .padding(.top, 6)
                    .padding(.bottom, 14)

                SectionLabel(text: "Display unit")
                unitChips

                SectionLabel(text: "Security", topPadding: 20)
                securityCard

                SectionLabel(text: "Danger zone", topPadding: 20)
                dangerZone

                Text("LightApp 0.1 · Core Lightning · Greenlight")
                    .font(Tokens.jetBrainsMono(12))
                    .foregroundStyle(Tokens.Faint)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.vertical, 24)
            }
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Display unit

    private static let unitOptions: [(value: String, label: String)] = [
        ("sat", "sat"), ("msat", "msat"), ("btc", "BTC"),
    ]

    private var unitChips: some View {
        HStack(spacing: 8) {
            ForEach(Self.unitOptions, id: \.value) { option in
                let on = unit == option.value
                Button {
                    unit = option.value
                    repository.displayUnit = option.value
                } label: {
                    Text(option.label)
                        .font(Tokens.manrope(13, .bold))
                        .foregroundStyle(on ? Tokens.Accent : Tokens.Dim)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(
                            on ? Tokens.Accent.opacity(0.1) : Tokens.Card,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(on ? Tokens.Accent.opacity(0.4) : Tokens.BorderSoft, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(SettingsPressFadeStyle())
            }
        }
    }

    // MARK: Security

    private var securityCard: some View {
        VStack(spacing: 0) {
            SettingsRow(
                icon: "lock",
                title: "Reveal recovery phrase",
                subtitle: "Anyone with these words controls your funds",
                chevron: true
            ) { onOpenSheet(.seed) }
            rowDivider
            SettingsRow(
                icon: "arrow.down.to.line",
                title: "Copy client.crt",
                subtitle: "Greenlight certificate · clipboard"
            ) {
                Task {
                    if let pem = await repository.loadDeveloperCertPem() {
                        copyToClipboard(label: "client.crt", value: pem, sensitive: true)
                    }
                }
            }
            rowDivider
            SettingsRow(
                icon: "arrow.down.to.line",
                title: "Copy client-key.pem",
                subtitle: "Keep this secret"
            ) {
                Task {
                    if let pem = await repository.loadDeveloperKeyPem() {
                        copyToClipboard(label: "client-key.pem", value: pem, sensitive: true)
                    }
                }
            }
            rowDivider
            SettingsRow(
                icon: "arrow.up.right.square",
                title: "Source code",
                subtitle: "github.com/olegfomenko/light-app",
                monoSubtitle: true
            ) {
                if let url = URL(string: "https://github.com/olegfomenko/light-app") {
                    openURL(url)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Tokens.Card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Tokens.BorderSoft, lineWidth: 1)
        )
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color(hex: 0x0AFFFFFF))
            .frame(height: 1)
    }

    // MARK: Danger zone

    private var dangerZone: some View {
        Button {
            onOpenSheet(.dropWallet)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.Red)
                }
                .frame(width: 32, height: 32)
                .background(Tokens.Red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Delete wallet data")
                        .font(Tokens.manrope(15, .bold))
                        .foregroundStyle(Tokens.Red)
                    Text("Wipes seed and certificates from this device")
                        .font(Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.Dim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Tokens.Red.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Tokens.Red.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(SettingsPressFadeStyle())
    }
}

// MARK: - Row

/// One tappable settings row: icon bubble, title + subtitle, optional chevron.
private struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String
    var chevron: Bool = false
    var monoSubtitle: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Tokens.Accent)
                }
                .frame(width: 32, height: 32)
                .background(Tokens.Accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Tokens.manrope(15, .bold))
                        .foregroundStyle(Tokens.Text)
                    Text(subtitle)
                        .font(monoSubtitle ? Tokens.jetBrainsMono(12.5) : Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.Dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.Faint)
                        .frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPressFadeStyle())
    }
}

/// Local copy of the component library's press feedback (that one is
/// file-private); the design has no ink splash — Android's `noRipple`.
private struct SettingsPressFadeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
