//
//  MainTab.swift
//  LightApp
//
//  The Main (home) tab: header with node status pill, on-chain balance card,
//  Lightning balance card, and the merged recent-activity list.
//  Port of android/src/main/java/app/light/wallet/ui/home/MainTab.kt.
//  Reference visuals: design/lightning-wallet.dc.html (Main screen section).
//

import SwiftUI

// MARK: - Recent item model

private struct RecentItem {
    let label: String
    let time: String
    let amount: String
    let amountColor: Color
    let iconColor: Color
    let chain: Bool
    let sort: UInt64
    let onClick: () -> Void
}

/// Dictionary key for the node's tracked outpoints (Kotlin: `txid to output`).
private struct OutpointKey: Hashable {
    let txid: String
    let vout: UInt32
}

/// Kotlin `String.ifBlank { null }` on an optional.
private func blankToNil(_ s: String?) -> String? {
    guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return s
}

// MARK: - Button styles

/// Pressed feedback without an ink splash (Android's `noRipple`).
private struct PressFadeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Filled accent capsule that brightens while pressed (design hover #FDE047).
private struct AccentFillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Tokens.AccentHi : Tokens.Accent, in: Capsule())
    }
}

// MARK: - MainTab

@MainActor
struct MainTab: View {
    let repository: WalletRepository
    let onOpenSheet: (WalletSheet) -> Void
    let onGoTransactions: () -> Void
    let onRecentInvoice: (InvoiceEntry) -> Void
    let onRecentPay: (PayListEntry) -> Void
    let onRecentTx: (String) -> Void

    init(
        repository: WalletRepository,
        onOpenSheet: @escaping (WalletSheet) -> Void,
        onGoTransactions: @escaping () -> Void,
        onRecentInvoice: @escaping (InvoiceEntry) -> Void,
        onRecentPay: @escaping (PayListEntry) -> Void,
        onRecentTx: @escaping (String) -> Void
    ) {
        self.repository = repository
        self.onOpenSheet = onOpenSheet
        self.onGoTransactions = onGoTransactions
        self.onRecentInvoice = onRecentInvoice
        self.onRecentPay = onRecentPay
        self.onRecentTx = onRecentTx
    }

    private var unit: DisplayUnit { DisplayUnit.from(stored: repository.displayUnit) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                onchainCard
                lightningCard
                recentSection
            }
            .padding(.horizontal, 18)
        }
        // The Main screen is the only one that auto-refreshes (every 30 s
        // while visible); everything else waits for pull-to-refresh or an
        // action. Entry + connState changes trigger an immediate refresh
        // (Kotlin: LaunchedEffect(tick, connState)).
        .refreshable {
            // Exactly the three RPCs Android's pull joins — no getinfo echo,
            // no transactions ride-along. The RPC budget is part of the spec.
            await repository.refreshFunds().value
            await repository.refreshInvoices().value
            await repository.refreshPays().value
        }
        .onAppear {
            repository.startMainAutoRefresh()
            if repository.node != nil { repository.refreshMain() }
        }
        .onDisappear {
            repository.stopMainAutoRefresh()
        }
        .onChange(of: repository.connState) {
            if repository.node != nil { repository.refreshMain() }
        }
    }

    // MARK: Header

    private var connChip: (text: String, color: Color) {
        switch repository.connState {
        case .connected: return ("Node running", Tokens.Green)
        case .connecting: return ("Connecting…", Tokens.Orange)
        case .error: return ("Offline", Tokens.Red)
        case .idle: return ("Idle", Tokens.Dim)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            LogoMark()
            Text("LightApp")
                .font(Tokens.spaceGrotesk(17, .bold))
                .foregroundStyle(Tokens.Text)
                .frame(maxWidth: .infinity, alignment: .leading)
            let chip = connChip
            HStack(spacing: 6) {
                Circle()
                    .fill(chip.color)
                    .frame(width: 6, height: 6)
                Text(chip.text)
                    .font(Tokens.manrope(12.5, .bold))
                    .foregroundStyle(chip.color)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(chip.color.opacity(0.08), in: Capsule())
            .overlay(Capsule().strokeBorder(chip.color.opacity(0.25), lineWidth: 1))
            .contentShape(Capsule())
            .onTapGesture {
                if case .error = repository.connState {
                    repository.connectInBackground(force: true)
                }
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 14)
    }

    // MARK: Bitcoin on-chain card

    private var onchainCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Text("₿")
                        .font(Tokens.spaceGrotesk(12, .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 22, height: 22)
                .background(Tokens.Btc, in: Circle())
                Text("Bitcoin · on-chain")
                    .font(Tokens.manrope(12.5, .bold))
                    .foregroundStyle(Tokens.Label)
            }
            // Design: one total figure (confirmed + unconfirmed), no
            // BTC-conversion/pending subtitle line.
            // Confirmed only: while our own send is confirming, the spent
            // input can still read "confirmed" alongside the unconfirmed
            // change output — summing both double-counts the balance.
            let chain = repository.funds.map { $0.onchainConfirmedMsat }
            BalanceText(amount: formatAmount(msat: chain, unit: unit), unit: unit.label)
                .padding(.top, 14)
            HStack(spacing: 10) {
                SoftPillButton(text: "Receive", icon: "arrow.down") { onOpenSheet(.receive) }
                SoftPillButton(text: "Send", icon: "arrow.up") { onOpenSheet(.sendChain) }
                MoreDot { onGoTransactions() }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xFF141B23), Color(hex: 0xFF10161C)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Tokens.Border, lineWidth: 1)
        )
    }

    // MARK: Lightning card

    private var lightningCard: some View {
        let nodeId = repository.connState.info?.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    BoltIcon(size: 13, color: Tokens.Accent)
                }
                .frame(width: 22, height: 22)
                .background(Tokens.Accent.opacity(0.15), in: Circle())
                Text("Lightning")
                    .font(Tokens.manrope(12.5, .bold))
                    .foregroundStyle(Tokens.Label)
                Spacer(minLength: 0)
                let chCount = repository.funds?.channels.count ?? 0
                Text("\(chCount) channels")
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Dim)
            }
            BalanceText(
                amount: formatAmount(msat: repository.funds?.outboundMsat, unit: unit),
                unit: unit.label,
                color: Tokens.Accent
            )
            .padding(.top, 14)
            Rectangle()
                .fill(Tokens.Border)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            Button {
                if let nodeId { copyToClipboard(label: "Node ID", value: nodeId) }
            } label: {
                HStack(spacing: 8) {
                    Text("Node ID")
                        .font(Tokens.manrope(12.5, .bold))
                        .foregroundStyle(Tokens.Dim)
                    Text(shortId(nodeId, 12))
                        .font(Tokens.jetBrainsMono(13))
                        .foregroundStyle(Tokens.TextMid)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    if nodeId != nil {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.Accent)
                    }
                }
                .padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressFadeStyle())
            .disabled(nodeId == nil)
            HStack(spacing: 10) {
                Button {
                    onOpenSheet(.newInvoice)
                } label: {
                    Text("Create invoice")
                        .font(Tokens.manrope(13.5, .bold))
                        .foregroundStyle(Tokens.AccentInk)
                        .lineLimit(1)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Capsule())
                }
                .buttonStyle(AccentFillStyle())
                SoftPillButton(text: "Pay invoice") { onOpenSheet(.pay(prefill: "")) }
                MoreDot { onOpenSheet(.nodeInfoSheet) }
            }
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xFF26200F), Color(hex: 0xFF181307)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Tokens.Accent.opacity(0.2), lineWidth: 1)
        )
        .padding(.top, 14)
    }

    // MARK: Recent activity

    /// Paid invoices + lightning payments + on-chain transactions, all derived
    /// from the shared repository state (Kotlin: `remember(funds, invoices,
    /// pays, transactions, connState, unit)`).
    private var recent: [RecentItem] {
        let now = UInt64(Date().timeIntervalSince1970)
        let tip = repository.connState.info?.blockheight ?? 0

        let inv: [RecentItem] = (repository.invoices ?? [])
            .filter { $0.status == "paid" }
            .map { i in
                RecentItem(
                    label: blankToNil(i.description) ?? i.label,
                    time: relativeTime(i.paidAt),
                    amount: "+" + formatAmount(msat: i.amountReceivedMsat, unit: unit),
                    amountColor: Tokens.Green, iconColor: Tokens.Green,
                    chain: false, sort: i.paidAt ?? 0,
                    onClick: { onRecentInvoice(i) }
                )
            }

        let sent: [RecentItem] = (repository.pays ?? []).map { p in
            RecentItem(
                label: blankToNil(p.description) ?? shortId(p.destination, 8),
                time: relativeTime(p.completedAt ?? p.createdAt),
                amount: "−" + formatAmount(msat: p.amountMsat, unit: unit),
                amountColor: Tokens.Text, iconColor: Tokens.Red,
                chain: false, sort: p.completedAt ?? p.createdAt,
                onClick: { onRecentPay(p) }
            )
        }

        // On-chain: whole transactions, valued as the net of the inputs and
        // outputs our node tracks (deposits positive, withdrawals negative).
        let tracked = Dictionary(
            (repository.funds?.outputs ?? []).map {
                (OutpointKey(txid: $0.txid, vout: $0.output), $0.amountMsat)
            },
            uniquingKeysWith: { _, last in last }
        )
        let chain: [RecentItem] = (repository.transactions ?? []).compactMap { tx in
            let inSum = tx.inputs.reduce(Int64(0)) {
                $0 + Int64(tracked[OutpointKey(txid: $1.txid, vout: $1.index)] ?? 0)
            }
            let outSum = tx.outputs.reduce(Int64(0)) {
                $0 + Int64(tracked[OutpointKey(txid: tx.txid, vout: $1.index)] ?? 0)
            }
            let net = outSum - inSum
            if inSum == 0 && outSum == 0 { return nil }
            let confirmed = tx.blockheight > 0
            let ts: UInt64
            if !confirmed || tip == 0 || tip < tx.blockheight {
                ts = now
            } else {
                let age = UInt64(tip - tx.blockheight) * 600
                ts = now >= age ? now - age : 0
            }
            return RecentItem(
                label: net >= 0 ? "Received bitcoin" : "Sent bitcoin",
                time: confirmed ? relativeTime(ts) : "confirming…",
                amount: (net >= 0 ? "+" : "−") + formatAmount(msat: net.magnitude, unit: unit),
                amountColor: net >= 0 ? Tokens.Green : Tokens.Text,
                iconColor: Tokens.Btc,
                chain: true, sort: ts,
                onClick: { onRecentTx(tx.txid) }
            )
        }

        return Array((inv + sent + chain).sorted { $0.sort > $1.sort }.prefix(4))
    }

    private var recentSection: some View {
        let items = recent
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                Text("Recent activity")
                    .font(Tokens.spaceGrotesk(15, .bold))
                    .foregroundStyle(Tokens.Text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 22)
            .padding(.bottom, 10)
            VStack(spacing: 8) {
                if items.isEmpty {
                    Text("No activity yet — create an invoice or get an on-chain address to receive funds.")
                        .font(Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.Faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    recentRow(item)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func recentRow(_ item: RecentItem) -> some View {
        Button(action: item.onClick) {
            HStack(spacing: 12) {
                RowIcon(bg: item.iconColor.opacity(0.1)) {
                    if item.chain {
                        Image(systemName: "bitcoinsign")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(item.iconColor)
                    } else {
                        BoltIcon(size: 15, color: item.iconColor)
                    }
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.label)
                        .font(Tokens.manrope(14, .bold))
                        .foregroundStyle(Tokens.Text)
                        .lineLimit(1)
                    Text(item.time)
                        .font(Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.Dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(item.amount)
                    .font(Tokens.spaceGrotesk(14, .semibold))
                    .foregroundStyle(item.amountColor)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Tokens.Card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Tokens.BorderSoft, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PressFadeStyle())
    }
}

// MARK: - More dot (round "…" button)

private struct MoreDot: View {
    let onClick: () -> Void

    var body: some View {
        Button(action: onClick) {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Tokens.TextMid)
                .frame(width: 44, height: 44)
                .background(Color(hex: 0x0FFFFFFF), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressFadeStyle())
    }
}

// MARK: - Logo mark

/// A 20×20-viewBox polygon scaled into the drawing rect.
private struct PolyShape: Shape {
    let pts: [(CGFloat, CGFloat)]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let scaled = pts.map { p in
            CGPoint(x: rect.minX + p.0 / 20 * rect.width,
                    y: rect.minY + p.1 / 20 * rect.height)
        }
        guard let first = scaled.first else { return path }
        path.move(to: first)
        for p in scaled.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}

/// The app logo, drawn to match the design SVG (Android ships it as the
/// `logo_lightapp_small` drawable; iOS has no bundled equivalent, so the
/// 34 pt mark is rendered in SwiftUI): dark radial ground, two faint accent
/// rings, and the two-tone gradient bolt with its soft shadow.
private struct LogoMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(hex: 0xFF241C09),
                            Color(hex: 0xFF120E05),
                            Color(hex: 0xFF070809),
                        ],
                        center: UnitPoint(x: 0.5, y: 0.42),
                        startRadius: 0, endRadius: 29
                    )
                )
            Circle()
                .strokeBorder(Tokens.Accent.opacity(0.25), lineWidth: 0.9)
                .frame(width: 15.3, height: 15.3)
            Circle()
                .strokeBorder(Tokens.Accent.opacity(0.12), lineWidth: 0.8)
                .frame(width: 26.6, height: 26.6)
            ZStack {
                BoltShape()
                    .fill(Color(hex: 0xFF0A0803).opacity(0.6))
                    .offset(x: 0.4, y: 0.7)
                PolyShape(pts: [(11, 1), (4, 11.5), (8.6, 11.5), (7.4, 19)])
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFFFF085), Color(hex: 0xFFFACC15)],
                            startPoint: .topLeading, endPoint: UnitPoint(x: 1, y: 0.3)
                        )
                    )
                PolyShape(pts: [(11, 1), (7.4, 19), (16, 8.5), (10.9, 8.5)])
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFEAB308), Color(hex: 0xFFB8860B)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: 21.9, height: 21.9)
            .offset(x: 0.3, y: 0.3)
        }
        .frame(width: 34, height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}
