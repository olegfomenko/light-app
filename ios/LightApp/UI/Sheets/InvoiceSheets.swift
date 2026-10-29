//
//  InvoiceSheets.swift
//  LightApp
//
//  Invoice creation (NewInvoiceSheet) and its result (InvoiceResultSheet).
//  Port of the same-named composables in
//  android/src/main/java/app/light/wallet/ui/sheets/SheetHost.kt.
//

import SwiftUI

// MARK: - New invoice

@MainActor
struct NewInvoiceSheet: View {
    let repository: WalletRepository
    let onOpenSheet: (WalletSheet) -> Void
    let onClose: () -> Void

    @State private var anyAmount = false
    @State private var amount = ""
    @State private var desc = ""
    @State private var expD = "7"
    @State private var expH = "0"
    @State private var expM = "0"
    @State private var showAdv = false
    @State private var customLabel = ""
    @State private var cltv = ""
    @State private var fallback = ""
    @State private var preimageAuto = true
    @State private var preimageHex = ""
    /// "default" | "true" | "false" | "scids"
    @State private var exposeMode = "default"
    @State private var exposeScids = ""
    @State private var busy = false
    @State private var error: String? = nil

    init(
        repository: WalletRepository,
        onOpenSheet: @escaping (WalletSheet) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.repository = repository
        self.onOpenSheet = onOpenSheet
        self.onClose = onClose
    }

    private var unit: DisplayUnit { DisplayUnit.from(stored: repository.displayUnit) }

    private static let exposeOptions: [(String, String)] = [
        ("default", "Default"), ("true", "True"), ("false", "False"), ("scids", "SCIDs"),
    ]

    var body: some View {
        let unit = self.unit

        SheetTitle(text: "Create invoice", onClose: onClose)

        // Amount label + "Any amount" switch on one row.
        HStack(spacing: 0) {
            Text("Amount (\(unit.label))")
                .font(Tokens.manrope(11.5, .bold))
                .foregroundStyle(Tokens.Dim)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 7) {
                DesignSwitch(checked: anyAmount) { anyAmount.toggle() }
                Text("Any amount")
                    .font(Tokens.manrope(11.5, .bold))
                    .foregroundStyle(Tokens.TextMid)
            }
            .contentShape(Rectangle())
            .onTapGesture { anyAmount.toggle() }
        }

        if !anyAmount {
            DesignField(
                value: Binding(
                    get: { amount },
                    set: { amount = filterAmountInput($0, unit: unit) }
                ),
                placeholder: {
                    switch unit {
                    case .SAT: return "25 000"
                    case .MSAT: return "25 000 000"
                    case .BTC: return "0.00025"
                    }
                }(),
                numeric: true,
                big: true
            )
            .padding(.top, 8)
        }

        FieldLabel(text: "Description", topPadding: 12)
        DesignField(value: $desc, placeholder: "What is this for?")

        FieldLabel(text: "Expiry", topPadding: 12)
        HStack(alignment: .top, spacing: 8) {
            expiryColumn("Days", $expD)
            expiryColumn("Hours", $expH)
            expiryColumn("Minutes", $expM)
        }

        Text(showAdv ? "Advanced ▲" : "Advanced ▼")
            .font(Tokens.manrope(12.5, .bold))
            .foregroundStyle(Tokens.Accent)
            .padding(.top, 10)
            .contentShape(Rectangle())
            .onTapGesture { showAdv.toggle() }

        if showAdv {
            advanced
        }

        if let error {
            Text(error)
                .font(Tokens.manrope(12.5))
                .foregroundStyle(Tokens.Red)
                .padding(.top, 10)
        }

        PillButton(
            text: busy ? "Creating…" : "Create invoice",
            enabled: !busy && (anyAmount || parseAmountToMsat(amount, unit: unit) != nil),
            height: 52
        ) {
            create()
        }
        .padding(.top, 18)
    }

    // MARK: Advanced disclosure

    @ViewBuilder
    private var advanced: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                tinyLabel("Label")
                DesignField(value: $customLabel, placeholder: "auto", mono: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                tinyLabel("CLTV")
                DesignField(
                    value: Binding(
                        get: { cltv },
                        set: { cltv = $0.filter { c in c.isNumber } }
                    ),
                    placeholder: "18",
                    numeric: true
                )
            }
            .frame(width: 110)
        }
        .padding(.top, 8)

        VStack(alignment: .leading, spacing: 6) {
            tinyLabel("Fallback address (optional)")
            DesignField(value: $fallback, placeholder: "bc1q…", mono: true)
        }
        .padding(.top, 8)

        HStack(spacing: 0) {
            tinyLabel("Preimage")
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 7) {
                DesignSwitch(checked: preimageAuto) { preimageAuto.toggle() }
                Text("Auto-generate")
                    .font(Tokens.manrope(12.5, .bold))
                    .foregroundStyle(Tokens.TextMid)
            }
            .contentShape(Rectangle())
            .onTapGesture { preimageAuto.toggle() }
        }
        .padding(.top, 10)

        if preimageAuto {
            Text("Random 32-byte preimage generated by the node")
                .font(Tokens.jetBrainsMono(12.5))
                .foregroundStyle(Tokens.Faint)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(hex: 0x08FFFFFF),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color(hex: 0x1AFFFFFF), lineWidth: 1)
                )
                .padding(.top, 6)
        } else {
            DesignField(
                value: Binding(
                    get: { preimageHex },
                    set: { preimageHex = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                ),
                placeholder: "64 hex chars",
                mono: true
            )
            .padding(.top, 6)
        }

        tinyLabel("Expose private channels")
            .padding(.top, 10)
            .padding(.bottom, 6)

        HStack(spacing: 8) {
            ForEach(Self.exposeOptions, id: \.0) { value, label in
                let on = exposeMode == value
                Text(label)
                    .font(Tokens.manrope(12.5, .bold))
                    .foregroundStyle(on ? Tokens.Accent : Tokens.Dim)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        on ? Tokens.Accent.opacity(0.1) : Tokens.CardDeep,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(
                                on ? Tokens.Accent.opacity(0.4) : Color(hex: 0x17FFFFFF),
                                lineWidth: 1
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .onTapGesture { exposeMode = value }
            }
        }

        if exposeMode == "scids" {
            DesignField(
                value: $exposeScids,
                placeholder: "848291x1204x1, 851002x88x0",
                mono: true
            )
            .padding(.top, 6)
        }

        Text("Boolean or a list of short_channel_ids — picking one form rules out the others")
            .font(Tokens.manrope(10.5))
            .foregroundStyle(Tokens.Faint)
            .padding(.top, 6)
    }

    // MARK: Pieces

    private func tinyLabel(_ text: String) -> some View {
        Text(text)
            .font(Tokens.manrope(10.5, .bold))
            .foregroundStyle(Tokens.Faint)
    }

    private func expiryColumn(_ label: String, _ value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            tinyLabel(label)
            DesignField(
                value: Binding(
                    get: { value.wrappedValue },
                    set: { value.wrappedValue = $0.filter { c in c.isNumber } }
                ),
                placeholder: "0",
                numeric: true
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Create

    private func create() {
        let unit = self.unit
        busy = true
        error = nil
        Task { @MainActor in
            // Kotlin ULong arithmetic wraps on overflow; mirror that instead
            // of trapping on absurd day counts.
            let days: UInt64 = UInt64(expD) ?? 0
            let hours: UInt64 = UInt64(expH) ?? 0
            let minutes: UInt64 = UInt64(expM) ?? 0
            let expiry: UInt64 = (days &* 86400) &+ (hours &* 3600) &+ (minutes &* 60)

            // gRPC only carries scid arrays; True = every private channel we
            // know, False = a filter matching nothing.
            let expose: [String]
            switch exposeMode {
            case "scids":
                expose = exposeScids
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            case "true":
                expose = (repository.channels ?? [])
                    .filter { $0.isPrivate == true }
                    .compactMap { $0.shortChannelId }
            case "false":
                expose = ["0x0x0"]
            default:
                expose = []
            }

            let labelBlank = customLabel
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let preimageBlank = preimageHex
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            do {
                let result = try await repository.createInvoice(params: CreateInvoiceParams(
                    amountMsat: anyAmount ? nil : parseAmountToMsat(amount, unit: unit),
                    description: desc,
                    label: labelBlank
                        ? "lightapp-\(Int64(Date().timeIntervalSince1970 * 1000))"
                        : customLabel,
                    expiry: expiry == 0 ? nil : expiry,
                    fallbacks: [fallback].filter {
                        !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    },
                    preimageHex: !preimageAuto ? (preimageBlank ? nil : preimageHex) : nil,
                    cltv: UInt32(cltv),
                    deschashonly: nil,
                    exposeprivatechannels: expose
                ))
                onOpenSheet(.newInvoiceResult(
                    bolt11: result.bolt11,
                    paymentHash: result.paymentHash,
                    expiresAt: result.expiresAt
                ))
            } catch {
                self.error = Self.errorMessage(error)
            }
            busy = false
        }
    }

    /// Kotlin `it.message` — unwrap the core's `CoreError.Msg` payload instead
    /// of showing the generated reflection dump.
    private static func errorMessage(_ error: Error) -> String {
        if case CoreError.Msg(let message) = error, !message.isEmpty { return message }
        return (error as NSError).localizedDescription
    }
}

// MARK: - Invoice result

struct InvoiceResultSheet: View {
    let bolt11: String
    let paymentHash: String
    let expiresAt: UInt64
    let onClose: () -> Void

    init(
        bolt11: String,
        paymentHash: String,
        expiresAt: UInt64,
        onClose: @escaping () -> Void
    ) {
        self.bolt11 = bolt11
        self.paymentHash = paymentHash
        self.expiresAt = expiresAt
        self.onClose = onClose
    }

    var body: some View {
        SheetTitle(text: "Invoice created", onClose: onClose)

        VStack(spacing: 14) {
            // Uppercase → QR alphanumeric mode, denser modules (as Android).
            QrView(text: bolt11.uppercased(), sizePt: 200)
            Text(shortId(bolt11, 22))
                .font(Tokens.jetBrainsMono(12.5))
                .foregroundStyle(Tokens.Dim)
            Text("Expires \(formatUnixTime(expiresAt))")
                .font(Tokens.manrope(12.5))
                .foregroundStyle(Tokens.Faint)
            PillButton(text: "Copy invoice", height: 48) {
                copyToClipboard(label: "Invoice", value: bolt11)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
