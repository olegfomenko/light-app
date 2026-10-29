//
//  InvoicesTab.swift
//  LightApp
//
//  Created/Payments lists with live in-flight payment cards.
//  Port of android/src/main/java/app/light/wallet/ui/invoices/InvoicesTab.kt.
//

import SwiftUI

struct InvoicesTab: View {
    let repository: WalletRepository
    let onOpenSheet: (WalletSheet) -> Void
    let segmentRequest: SegmentRequest

    /// 0 = created, 1 = payments.
    @State private var segment = 0

    init(
        repository: WalletRepository,
        onOpenSheet: @escaping (WalletSheet) -> Void,
        segmentRequest: SegmentRequest
    ) {
        self.repository = repository
        self.onOpenSheet = onOpenSheet
        self.segmentRequest = segmentRequest
    }

    // MARK: Derived state

    private var unit: DisplayUnit {
        DisplayUnit.from(stored: repository.displayUnit)
    }

    private var invoices: [InvoiceEntry] {
        (repository.invoices ?? []).sorted { $0.createdIndex > $1.createdIndex }
    }

    private var pays: [PayListEntry] {
        (repository.pays ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    /// Payments started this session that are still in flight.
    private var livePayments: [ActivePayment] {
        repository.activePayments.filter { $0.status == .PAYING || $0.status == .PENDING }
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Text("Invoices")
                .font(Tokens.spaceGrotesk(24, .bold))
                .foregroundStyle(Tokens.Text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
                .padding(.bottom, 14)

            segmentedControl

            ScrollView {
                LazyVStack(spacing: 8) {
                    if segment == 0 {
                        createdList
                    } else {
                        paymentsList
                    }
                }
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .refreshable {
                // Kotlin joined the two refresh jobs sequentially.
                await repository.refreshInvoices().value
                await repository.refreshPays().value
            }

            ctaRow
        }
        .padding(.horizontal, 18)
        // Navigation elsewhere (recent activity, payment started) picks a
        // segment; `initial: true` mirrors LaunchedEffect re-running on entry.
        .onChange(of: segmentRequest, initial: true) {
            if segmentRequest.token > 0 { segment = segmentRequest.segment }
        }
        // First entry only; afterwards pull-to-refresh or actions update state.
        .onChange(of: repository.connState, initial: true) {
            if repository.node != nil {
                repository.fetchIfNeeded(.invoices)
                repository.fetchIfNeeded(.pays)
            }
        }
    }

    // MARK: Segmented control

    private var segmentedControl: some View {
        let pendingCount = livePayments.count
        return HStack(spacing: 4) {
            segmentButton("Created", on: segment == 0) { segment = 0 }
            segmentButton(
                pendingCount > 0 ? "Payments · \(pendingCount)" : "Payments",
                on: segment == 1
            ) { segment = 1 }
        }
        .padding(4)
        .background(Tokens.Card, in: Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Border, lineWidth: 1))
    }

    private func segmentButton(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(Tokens.manrope(13, .bold))
                .foregroundStyle(on ? Tokens.Text : Tokens.Dim)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(on ? Tokens.Field : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Lists

    @ViewBuilder
    private var createdList: some View {
        let invoices = self.invoices
        ForEach(invoices, id: \.createdIndex) { inv in
            InvoiceRow(inv: inv, unit: unit) { onOpenSheet(.invoiceDetail(inv)) }
        }
        if invoices.isEmpty {
            Empty(text: "No invoices created yet.")
        }
    }

    @ViewBuilder
    private var paymentsList: some View {
        let live = livePayments
        let liveInvstrings = Set(live.map(\.invstring))
        let pays = self.pays
        ForEach(live) { p in
            ActivePayRow(
                status: p.status,
                subtitle: p.description ?? shortId(p.invstring, 12),
                mono: p.description == nil
            ) { onOpenSheet(.activePaymentDetail(paymentId: p.id)) }
        }
        // Don't also render the listpays row for a payment we're still
        // showing as a live in-flight card.
        let completed = pays.filter {
            !liveInvstrings.contains($0.bolt11 ?? "") && !liveInvstrings.contains($0.bolt12 ?? "")
        }
        ForEach(completed, id: \.paymentHash) { p in
            PayRow(p: p, unit: unit) { onOpenSheet(.paymentDetail(p)) }
        }
        if pays.isEmpty && live.isEmpty {
            Empty(text: "No payments yet.")
        }
    }

    // MARK: Bottom CTA row

    private var ctaRow: some View {
        HStack(spacing: 10) {
            PillButton(
                text: segment == 0 ? "Create invoice" : "Pay invoice",
                height: 50
            ) {
                onOpenSheet(segment == 0 ? .newInvoice : .pay(prefill: ""))
            }
            if segment == 1 {
                OutlinePillButton(text: "Check route", height: 50) {
                    onOpenSheet(.checkRoute)
                }
            }
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Rows

/// Kotlin `String?.ifBlank { null } ?: fallback`.
private func blankToNil(_ s: String?) -> String? {
    guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return s
}

/// The design's pressed state: no ink splash, just a subtle fade.
private struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Card chrome shared by the three row types (#11171E, r14, hairline border).
private struct RowCard: ViewModifier {
    var borderColor: Color = Tokens.BorderSoft

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Tokens.Card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct InvoiceRow: View {
    let inv: InvoiceEntry
    let unit: DisplayUnit
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 12) {
                RowIcon(bg: Tokens.Accent.opacity(0.07)) {
                    BoltIcon(size: 14, color: Tokens.Accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(blankToNil(inv.description) ?? inv.label)
                        .font(Tokens.manrope(15, .bold))
                        .foregroundStyle(Tokens.Text)
                        .lineLimit(1)
                    Text(inv.status == "paid" ? relativeTime(inv.paidAt) : formatUnixTime(inv.expiresAt))
                        .font(Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.Dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatAmount(msat: inv.amountMsat, unit: unit))
                        .font(Tokens.spaceGrotesk(14.5, .semibold))
                        .foregroundStyle(Tokens.Text)
                    StatusBadge(text: inv.status, color: statusColor(inv.status))
                }
            }
            .modifier(RowCard())
        }
        .buttonStyle(RowPressStyle())
    }
}

private struct PayRow: View {
    let p: PayListEntry
    let unit: DisplayUnit
    let onClick: () -> Void

    var body: some View {
        let c = statusColor(p.status)
        Button(action: onClick) {
            HStack(spacing: 12) {
                RowIcon(bg: c.opacity(0.1)) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(blankToNil(p.description) ?? shortId(p.destination, 8))
                        .font(Tokens.manrope(15, .bold))
                        .foregroundStyle(Tokens.Text)
                        .lineLimit(1)
                    Text(relativeTime(p.completedAt ?? p.createdAt))
                        .font(Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.Dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text("−" + formatAmount(msat: p.amountMsat, unit: unit))
                        .font(Tokens.spaceGrotesk(14.5, .semibold))
                        .foregroundStyle(Tokens.Text)
                    StatusBadge(text: p.status, color: c)
                }
            }
            .modifier(RowCard())
        }
        .buttonStyle(RowPressStyle())
    }
}

/// Live in-flight payment card — orange border, hourglass icon.
private struct ActivePayRow: View {
    let status: ActivePaymentStatus
    let subtitle: String
    let mono: Bool
    let onClick: () -> Void

    var body: some View {
        let pending = status == .PENDING
        Button(action: onClick) {
            HStack(spacing: 12) {
                RowIcon(bg: Tokens.Orange.opacity(0.1)) {
                    Image(systemName: "hourglass.tophalf.filled")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Tokens.Orange)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(pending ? "Payment pending" : "Routing payment…")
                        .font(Tokens.manrope(15, .bold))
                        .foregroundStyle(Tokens.Text)
                    Text(subtitle)
                        .font(mono ? Tokens.jetBrainsMono(12.5) : Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.Faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusBadge(text: pending ? "pending" : "paying", color: Tokens.Orange)
            }
            .modifier(RowCard(borderColor: Tokens.Orange.opacity(0.3)))
        }
        .buttonStyle(RowPressStyle())
    }
}
