//
//  ReceiveSendSheets.swift
//  LightApp
//
//  On-chain receive (newaddr + QR) and send (withdraw) sheets.
//  Port of ReceiveSheet + SendChainSheet from
//  android/src/main/java/app/light/wallet/ui/sheets/SheetHost.kt.
//

import SwiftUI

/// Kotlin `e.message` for sheet-local one-shot RPCs — the core surfaces every
/// failure as `CoreError.Msg`, whose generated description is a reflection
/// dump, so unwrap the message ourselves (same rule as WalletRepository).
private func sheetErrorText(_ error: Error) -> String {
    if case CoreError.Msg(let message) = error, !message.isEmpty { return message }
    let d = (error as NSError).localizedDescription
    return d.isEmpty ? "error" : d
}

// ─────────────────────────── Receive (on-chain) ───────────────────────────

@MainActor
struct ReceiveSheet: View {
    let repository: WalletRepository
    let onClose: () -> Void

    @State private var address: String? = nil
    @State private var error: String? = nil

    init(repository: WalletRepository, onClose: @escaping () -> Void) {
        self.repository = repository
        self.onClose = onClose
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: "Receive bitcoin", onClose: onClose)
            VStack(spacing: 14) {
                if let addr = address {
                    // QR encodes the uppercased address (smaller alphanumeric
                    // QR mode); the copy row keeps the original casing.
                    QrView(text: addr.uppercased())

                    Button {
                        copyToClipboard(label: "Address", value: addr)
                    } label: {
                        HStack(spacing: 0) {
                            Text(addr)
                                .font(Tokens.jetBrainsMono(12))
                                .foregroundStyle(Tokens.TextMid)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 15)
                        .padding(.vertical, 13)
                        .background(Tokens.Field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(Tokens.Border, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Text("bech32 · newaddr · a fresh address is generated after each use")
                        .font(Tokens.manrope(11.5))
                        .foregroundStyle(Tokens.Faint)
                        .multilineTextAlignment(.center)

                    OutlinePillButton(text: "Generate new address", height: 46) { generate() }
                } else if let error {
                    Text(error)
                        .font(Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.Red)
                } else {
                    Text("Generating address…")
                        .font(Tokens.manrope(14))
                        .foregroundStyle(Tokens.Dim)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .task { generate() }
    }

    private func generate() {
        Task { @MainActor in
            do {
                let result = try await repository.requireNode().newAddress(addresstype: "bech32")
                address = result.bech32
            } catch {
                self.error = sheetErrorText(error)
            }
        }
    }
}

// ─────────────────────────── Send (on-chain) ───────────────────────────

@MainActor
struct SendChainSheet: View {
    let repository: WalletRepository
    let onClose: () -> Void

    @State private var addr = ""
    @State private var amount = ""
    @State private var sendAll = false
    @State private var feerate = "normal"
    @State private var busy = false
    @State private var error: String? = nil
    @State private var txid: String? = nil

    init(repository: WalletRepository, onClose: @escaping () -> Void) {
        self.repository = repository
        self.onClose = onClose
    }

    private var unit: DisplayUnit { DisplayUnit.from(stored: repository.displayUnit) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: "Send on-chain", onClose: onClose)
            if let txid {
                success(txid)
            } else {
                form
            }
        }
    }

    // MARK: Success

    @ViewBuilder
    private func success(_ txid: String) -> some View {
        Text("Broadcast ✓")
            .font(Tokens.spaceGrotesk(15, .bold))
            .foregroundStyle(Tokens.Green)
        Text(txid)
            .font(Tokens.jetBrainsMono(12.5))
            .foregroundStyle(Tokens.Dim)
            .padding(.top, 8)
            .padding(.bottom, 16)
        PillButton(text: "Done") { onClose() }
    }

    // MARK: Form

    @ViewBuilder
    private var form: some View {
        let unit = self.unit
        let availableSatMsat = (repository.funds.map { $0.onchainConfirmedMsat / 1000 } ?? 0) * 1000

        FieldLabel(text: "Destination address")
        DesignField(value: $addr, placeholder: "bc1q…", mono: true)

        FieldLabel(text: "Amount (\(unit.label))", topPadding: 12)
        DesignField(
            value: Binding(
                get: { amount },
                set: { newValue in
                    amount = filterAmountInput(newValue, unit: unit)
                    sendAll = false
                }
            ),
            placeholder: "0",
            numeric: true,
            big: true
        )

        HStack(alignment: .top, spacing: 0) {
            Text("Available: \(formatAmount(msat: availableSatMsat, unit: unit)) \(unit.label)")
                .font(Tokens.manrope(11.5))
                .foregroundStyle(Tokens.Faint)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Send max")
                .font(Tokens.manrope(11.5, .bold))
                .foregroundStyle(Tokens.Accent)
                .contentShape(Rectangle())
                .onTapGesture {
                    // Fill the field with the full confirmed balance in the
                    // selected unit; the RPC then uses all=true.
                    sendAll = true
                    amount = formatAmount(msat: availableSatMsat, unit: unit)
                        .replacingOccurrences(of: " ", with: "")
                }
        }
        .padding(.top, 8)

        FieldLabel(text: "Feerate", topPadding: 12)
        FeerateChips(selected: $feerate)

        if let error {
            Text(error)
                .font(Tokens.manrope(12.5))
                .foregroundStyle(Tokens.Red)
                .padding(.top, 10)
        }

        PillButton(
            text: busy ? "Broadcasting…" : "Send on-chain",
            enabled: !busy
                && !addr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && parseAmountToMsat(amount, unit: unit) != nil
        ) { send() }
            .padding(.top, 18)
    }

    // MARK: Withdraw

    private func send() {
        let unit = self.unit
        busy = true
        error = nil
        Task { @MainActor in
            do {
                let node = try repository.requireNode()
                let result = try await repository.performGuardedRPC { try await node.withdraw(params: WithdrawParams(
                    destination: addr.trimmingCharacters(in: .whitespacesAndNewlines),
                    // msat -> sat floors, exactly like the Kotlin `/ 1000uL`.
                    amountSat: sendAll ? 0 : (parseAmountToMsat(amount, unit: unit) ?? 0) / 1000,
                    all: sendAll,
                    minconf: nil,
                    feerate: feerate
                )) }
                txid = result.txid
            } catch {
                self.error = sheetErrorText(error)
            }
            busy = false
        }
    }
}
