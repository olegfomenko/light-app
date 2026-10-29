//
//  DetailSheets.swift
//  LightApp
//
//  Read-only detail sheets: invoice detail, historical payment detail, and
//  the live active-payment sheet. Port of InvoiceDetailSheet /
//  PaymentDetailSheet / ActivePaymentSheet in
//  android/src/main/java/app/light/wallet/ui/sheets/SheetHost.kt.
//

import SwiftUI

// MARK: - Invoice detail

@MainActor
struct InvoiceDetailSheet: View {
    let repository: WalletRepository
    let invoice: InvoiceEntry
    let onClose: () -> Void

    init(repository: WalletRepository, invoice: InvoiceEntry, onClose: @escaping () -> Void) {
        self.repository = repository
        self.invoice = invoice
        self.onClose = onClose
    }

    var body: some View {
        let unit = DisplayUnit.from(stored: repository.displayUnit)

        SheetTitle(text: "Invoice", onClose: onClose)

        VStack(spacing: 0) {
            if invoice.status == "unpaid", let bolt11 = invoice.bolt11 {
                // Uppercase → QR alphanumeric mode, denser modules (as Android).
                QrView(text: bolt11.uppercased(), sizePt: 164)
            }
            Text(formatAmount(msat: invoice.amountMsat, unit: unit) + " " + unit.label)
                .font(Tokens.spaceGrotesk(30, .semibold))
                .kerning(-0.5)
                .foregroundStyle(statusColor(invoice.status))
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)

        KvPanel(rows: rows(unit: unit))

        if let bolt11 = invoice.bolt11 {
            OutlinePillButton(text: "Copy bolt11") {
                copyToClipboard(label: "Invoice", value: bolt11)
            }
            .padding(.top, 14)
        }
    }

    private func rows(unit: DisplayUnit) -> [(String, String, Bool)] {
        var rows: [(String, String, Bool)] = [
            ("Status", invoice.status, false),
            ("Description", invoice.description ?? "—", false),
            ("Label", invoice.label, true),
            ("Payment hash", invoice.paymentHash, true),
        ]
        if let preimage = invoice.paymentPreimage {
            rows.append(("Preimage", preimage, true))
        }
        rows.append(("Expires", formatUnixTime(invoice.expiresAt), false))
        if let paidAt = invoice.paidAt {
            rows.append(("Paid at", formatUnixTime(paidAt), false))
        }
        if let received = invoice.amountReceivedMsat {
            rows.append(("Received", formatAmountFull(msat: received, unit: unit), false))
        }
        return rows
    }
}

// MARK: - Payment detail (listpays history entry)

@MainActor
struct PaymentDetailSheet: View {
    let repository: WalletRepository
    let pay: PayListEntry
    let onClose: () -> Void

    init(repository: WalletRepository, pay: PayListEntry, onClose: @escaping () -> Void) {
        self.repository = repository
        self.pay = pay
        self.onClose = onClose
    }

    var body: some View {
        let unit = DisplayUnit.from(stored: repository.displayUnit)

        SheetTitle(text: "Payment", onClose: onClose)

        VStack(spacing: 0) {
            Text("−" + formatAmount(msat: pay.amountMsat, unit: unit) + " " + unit.label)
                .font(Tokens.spaceGrotesk(30, .semibold))
                .kerning(-0.5)
                .foregroundStyle(statusColor(pay.status))
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)

        KvPanel(rows: rows(unit: unit))
    }

    private func rows(unit: DisplayUnit) -> [(String, String, Bool)] {
        // Kotlin: sentMsat - amountMsat, only when both exist and no underflow.
        let fee: UInt64? = {
            guard let sent = pay.amountSentMsat, let amount = pay.amountMsat,
                  sent >= amount else { return nil }
            return sent - amount
        }()
        // Kotlin `description?.ifBlank { null }`: blank collapses to nil, a
        // non-blank value stays untrimmed.
        let description: String? = {
            guard let d = pay.description,
                  !d.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return d
        }()

        var rows: [(String, String, Bool)] = [
            ("Status", pay.status, false),
            ("Description", description ?? "—", description != nil),
            ("Destination", pay.destination ?? "—", true),
            ("Fee", formatAmountFull(msat: fee, unit: unit), false),
            ("Created", formatUnixTime(pay.createdAt), false),
        ]
        if let completedAt = pay.completedAt {
            rows.append(("Completed", formatUnixTime(completedAt), false))
        }
        rows.append(("Payment hash", pay.paymentHash, true))
        if let preimage = pay.preimage {
            rows.append(("Preimage", preimage, true))
        }
        if let parts = pay.numberOfParts {
            rows.append(("Parts", String(parts), false))
        }
        return rows
    }
}

// MARK: - Active payment (live)

/// Live: keeps rendering the latest state of this payment while it routes —
/// the repository is `@Observable`, so every `activePayments` update re-renders
/// this body (the Swift analogue of Android's `collectAsState()`).
@MainActor
struct ActivePaymentSheet: View {
    let repository: WalletRepository
    let paymentId: Int64
    let onClose: () -> Void

    init(repository: WalletRepository, paymentId: Int64, onClose: @escaping () -> Void) {
        self.repository = repository
        self.paymentId = paymentId
        self.onClose = onClose
    }

    var body: some View {
        let unit = DisplayUnit.from(stored: repository.displayUnit)
        let payment = repository.activePayments.first { $0.id == paymentId }

        SheetTitle(text: "Payment", onClose: onClose)

        if let p = payment {
            let heroColor = Self.heroColor(p.status)

            VStack(spacing: 0) {
                if p.status == .PAYING {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Tokens.Orange)
                        // Default UIKit spinner is ~20 pt; scale to Android's 28 dp.
                        .scaleEffect(1.4)
                        .frame(width: 28, height: 28)
                        .padding(.bottom, 12)
                }
                Text(Self.heroText(p, unit: unit))
                    .font(Tokens.spaceGrotesk(30, .semibold))
                    .kerning(-0.5)
                    .foregroundStyle(heroColor)
                    .multilineTextAlignment(.center)
                Text("via xpay" + (p.status == .PAYING ? " — routing…" : ""))
                    .font(Tokens.manrope(11.5))
                    .foregroundStyle(Tokens.Faint)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 16)

            KvPanel(
                rows: Self.rows(p, unit: unit),
                valueColor: { $0 == "Error" ? Tokens.Red : Tokens.TextMid }
            )
        } else {
            Text("Payment record not found.")
                .font(Tokens.manrope(14))
                .foregroundStyle(Tokens.Dim)
        }
    }

    private static func heroText(_ p: ActivePayment, unit: DisplayUnit) -> String {
        if let amount = p.amountMsat {
            return "−" + formatAmount(msat: amount, unit: unit) + " " + unit.label
        }
        switch p.status {
        case .PAYING: return "Routing…"
        case .PENDING: return "Pending — still in flight"
        case .COMPLETE: return "Paid"
        case .FAILED: return "Failed"
        }
    }

    private static func heroColor(_ status: ActivePaymentStatus) -> Color {
        switch status {
        case .PAYING, .PENDING: return Tokens.Orange
        case .COMPLETE: return Tokens.Green
        case .FAILED: return Tokens.Red
        }
    }

    /// Kotlin `status.name.lowercase()`.
    private static func statusName(_ status: ActivePaymentStatus) -> String {
        switch status {
        case .PAYING: return "paying"
        case .PENDING: return "pending"
        case .COMPLETE: return "complete"
        case .FAILED: return "failed"
        }
    }

    private static func rows(_ p: ActivePayment, unit: DisplayUnit) -> [(String, String, Bool)] {
        var rows: [(String, String, Bool)] = [
            ("Status", statusName(p.status), false),
        ]
        if let description = p.description {
            rows.append(("Description", description, false))
        }
        rows.append(("Invoice", shortId(p.invstring, 20), true))
        if let fee = p.feeMsat {
            rows.append(("Fee", formatAmountFull(msat: fee, unit: unit), false))
        }
        if let preimage = p.preimage {
            rows.append(("Preimage", preimage, true))
        }
        if let error = p.error {
            rows.append(("Error", error, false))
        }
        return rows
    }
}
