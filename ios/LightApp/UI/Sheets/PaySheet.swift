//
//  PaySheet.swift
//  LightApp
//
//  The "Pay" (xpay) sheet: paste an invoice, watch it decode live, optionally
//  tune the xpay knobs, then fire the payment off in the background.
//  Port of `PaySheet` in
//  android/src/main/java/app/light/wallet/ui/sheets/SheetHost.kt.
//  Reference visuals: design/lightning-wallet.dc.html (PAY section).
//

import SwiftUI

@MainActor
struct PaySheet: View {
    let repository: WalletRepository
    let onPaymentStarted: (Int64) -> Void
    let onClose: () -> Void

    @State private var inv: String
    @State private var decoded: DecodedInvoice? = nil
    @State private var showAdv = false
    @State private var maxFee = ""
    @State private var retryFor = ""
    @State private var maxDelay = ""
    @State private var partial = ""
    @State private var layers = ""
    @State private var amountOverride = ""
    @State private var error: String? = nil
    @State private var decodeError: String? = nil
    @State private var decoding = false

    init(
        repository: WalletRepository,
        prefill: String,
        onPaymentStarted: @escaping (Int64) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.repository = repository
        self.onPaymentStarted = onPaymentStarted
        self.onClose = onClose
        _inv = State(initialValue: prefill)
    }

    var body: some View {
        let unit = DisplayUnit.from(stored: repository.displayUnit)
        let trimmedInv = inv.trimmingCharacters(in: .whitespacesAndNewlines)

        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: "Pay", onClose: onClose, badge: "xpay")

            // Latest design: the invoice field stands alone, no label above.
            DesignField(value: invBinding, placeholder: "lnbc…", mono: true, lines: 3)

            if decoded == nil && decodeError == nil && trimmedInv.count > 20 {
                Text("Decoding…")
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Dim)
                    .padding(.top, 10)
            }
            if let decodeError {
                Text("Can't decode: \(decodeError)")
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Red)
                    .padding(.top, 10)
            }
            if let d = decoded {
                decodePreview(d, unit: unit)
                if d.amountMsat == nil {
                    FieldLabel(text: "Amount to pay (\(unit.label))", topPadding: 12)
                    DesignField(
                        value: amountBinding(unit: unit),
                        placeholder: "0",
                        numeric: true,
                        big: true
                    )
                }
            }

            Text(showAdv ? "xpay options ▲" : "xpay options ▼")
                .font(Tokens.manrope(12.5, .bold))
                .foregroundStyle(Tokens.Accent)
                .padding(.top, 10)
                .contentShape(Rectangle())
                .onTapGesture { showAdv.toggle() }

            if showAdv {
                advancedOptions(unit: unit)
            }

            // xpay runs asynchronously; the sheet is replaced by the live
            // payment detail, so the user must know nothing is blocked.
            Text("Payment runs in the background — keep using the app while it routes.")
                .font(Tokens.manrope(11.5))
                .lineSpacing(3)
                .foregroundStyle(Tokens.OrangeSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Tokens.Orange.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Tokens.Orange.opacity(0.2), lineWidth: 1)
                )
                .padding(.top, 12)

            if let error {
                Text(error)
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Red)
                    .padding(.top, 10)
            }

            let amountKnown = decoded?.amountMsat != nil
                || parseAmountToMsat(amountOverride, unit: unit) != nil
            let payMsat = decoded?.amountMsat ?? parseAmountToMsat(amountOverride, unit: unit)
            // Never pay until decode of the *current* invoice text has finished.
            let payEnabled = !trimmedInv.isEmpty && decoded != nil && !decoding && amountKnown

            PillButton(
                text: "Pay" + (payMsat.map { " " + formatAmount(msat: $0, unit: unit) + " " + unit.label } ?? ""),
                enabled: payEnabled,
                height: 52,
                bolt: true
            ) {
                pay(unit: unit)
            }
            .padding(.top, 14)
        }
        .task(id: inv) {
            // Reset everything derived from the previous invoice so a stale
            // amount or decode can never be paid against a newly-pasted
            // invoice (the binding's set already cleared synchronously; this
            // also covers the first run with `prefill`).
            decoded = nil
            decodeError = nil
            amountOverride = ""
            decoding = false
            let text = inv.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count > 20 else { return }
            decoding = true
            do {
                try await Task.sleep(for: .milliseconds(350)) // debounce while pasting/typing
                let node = try repository.requireNode()
                let d = try await node.decode(invstring: text)
                guard !Task.isCancelled else { return } // superseded input; drop silently
                decoded = d
            } catch is CancellationError {
                return // newer input took over; its task owns the state now
            } catch {
                guard !Task.isCancelled else { return }
                decodeError = Self.message(of: error, fallback: "could not decode invoice")
            }
            decoding = false
        }
    }

    // MARK: Decode preview

    private func decodePreview(_ d: DecodedInvoice, unit: DisplayUnit) -> some View {
        let expiresAt: UInt64? = {
            guard let created = d.createdAt, let expiry = d.expiry else { return nil }
            return created + expiry
        }()
        return VStack(alignment: .leading, spacing: 8) {
            DecRow(
                label: "Amount",
                value: d.amountMsat.map { formatAmount(msat: $0, unit: unit) + " " + unit.label } ?? "any amount"
            )
            DecRow(label: "Description", value: d.description ?? d.offerDescription ?? "—")
            DecRow(label: "Payee", value: shortId(d.payee, 10), mono: true)
            DecRow(label: "Expires", value: expiresIn(expiresAt), orange: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Tokens.Accent.opacity(0.05),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Tokens.Accent.opacity(0.18), lineWidth: 1)
        )
        .padding(.top, 12)
    }

    // MARK: xpay options

    @ViewBuilder
    private func advancedOptions(unit: DisplayUnit) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                advLabel("maxfee (\(unit.label))")
                DesignField(value: maxFeeBinding(unit: unit), placeholder: "auto", numeric: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                advLabel("retry_for (s)")
                DesignField(value: digitsBinding($retryFor), placeholder: "60", numeric: true)
            }
        }
        .padding(.top, 8)
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                advLabel("maxdelay")
                DesignField(value: digitsBinding($maxDelay), placeholder: "", numeric: true)
            }
            VStack(alignment: .leading, spacing: 6) {
                advLabel("partial_msat")
                // Raw RPC argument — always msat, never the display unit.
                DesignField(value: digitsBinding($partial), placeholder: "", numeric: true)
            }
        }
        .padding(.top, 8)
        VStack(alignment: .leading, spacing: 6) {
            advLabel("layers (askrene, comma-separated)")
            DesignField(value: $layers, placeholder: "", mono: true)
        }
        .padding(.top, 8)
    }

    private func advLabel(_ text: String) -> some View {
        Text(text)
            .font(Tokens.manrope(10.5, .bold))
            .foregroundStyle(Tokens.Faint)
    }

    // MARK: Bindings

    /// Invoice input: any edit synchronously invalidates the previous decode
    /// so the Pay button can never fire against stale results (the debounced
    /// `.task(id:)` then re-decodes).
    private var invBinding: Binding<String> {
        Binding(
            get: { inv },
            set: { newValue in
                guard newValue != inv else { return }
                inv = newValue
                decoded = nil
                decodeError = nil
                amountOverride = ""
                decoding = false
            }
        )
    }

    private func amountBinding(unit: DisplayUnit) -> Binding<String> {
        Binding(
            get: { amountOverride },
            set: { amountOverride = filterAmountInput($0, unit: unit) }
        )
    }

    private func maxFeeBinding(unit: DisplayUnit) -> Binding<String> {
        Binding(
            get: { maxFee },
            set: { maxFee = filterAmountInput($0, unit: unit) }
        )
    }

    private func digitsBinding(_ source: Binding<String>) -> Binding<String> {
        Binding(
            get: { source.wrappedValue },
            set: { source.wrappedValue = $0.filter { $0.isNumber } }
        )
    }

    // MARK: Dispatch

    private func pay(unit: DisplayUnit) {
        error = nil
        let id = repository.startPayment(
            command: .xpay(XpayParams(
                invstring: inv.trimmingCharacters(in: .whitespacesAndNewlines),
                amountMsat: decoded?.amountMsat == nil
                    ? parseAmountToMsat(amountOverride, unit: unit)
                    : nil,
                maxfeeMsat: parseAmountToMsat(maxFee, unit: unit),
                layers: layers
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty },
                retryFor: UInt32(retryFor),
                partialMsat: UInt64(partial),
                maxdelay: UInt32(maxDelay)
            )),
            description: decoded?.description ?? decoded?.offerDescription
        )
        // Close first: the host's onPaymentStarted replaces this sheet with
        // the live payment detail, and that replacement must be what survives.
        onClose()
        onPaymentStarted(id)
    }

    /// Kotlin `e.message ?: fallback` — unwrap the core's `CoreError.Msg`
    /// instead of showing the generated reflection dump.
    private static func message(of error: Error, fallback: String) -> String {
        if case CoreError.Msg(let message) = error, !message.isEmpty { return message }
        let d = (error as NSError).localizedDescription
        return d.isEmpty ? fallback : d
    }
}
