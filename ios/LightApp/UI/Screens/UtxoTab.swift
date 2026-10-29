//
//  UtxoTab.swift
//  LightApp
//
//  On-chain outputs list with status filter chips; rows link to mempool.space.
//  Port of android/src/main/java/app/light/wallet/ui/utxo/UtxoTab.kt (plus the
//  small helpers it imports from ui/transactions/TransactionsTab.kt —
//  openMempool + utxoStatusColor are file-private in the Swift TransactionsTab,
//  so this file carries its own copies).
//

import SwiftUI

private let FILTERS = ["unconfirmed", "confirmed", "spent", "immature"]

/// Same table as Android's `utxoStatusColor` in TransactionsTab.kt.
private func utxoStatusColor(_ status: String) -> Color {
    switch status {
    case "confirmed": return Tokens.Green
    case "unconfirmed": return Tokens.Orange
    case "immature": return Tokens.Purple
    default: return Tokens.Faint // spent
    }
}

/// Opens a mempool.space path ("tx/<txid>", "address/<addr>") in the browser —
/// Android's `openMempool` from the transactions package.
private func openMempool(_ openURL: OpenURLAction, path: String) {
    if let url = URL(string: "https://mempool.space/\(path)") {
        openURL(url)
    }
}

/// Kotlin `String.replaceFirstChar { it.uppercase() }`.
private func capitalizeFirst(_ s: String) -> String {
    guard let first = s.first else { return s }
    return first.uppercased() + s.dropFirst()
}

extension OnchainOutput {
    /// Android's LazyColumn key: "txid:output".
    fileprivate var utxoKey: String { "\(txid):\(output)" }
}

@MainActor
struct UtxoTab: View {
    let repository: WalletRepository

    @State private var filter = "confirmed"
    @Environment(\.openURL) private var openURL

    init(repository: WalletRepository) {
        self.repository = repository
    }

    var body: some View {
        let funds = repository.funds
        let unit = DisplayUnit.from(stored: repository.displayUnit)
        // Newest first: unconfirmed (no height) on top, then descending
        // height. Decorated sort keeps Kotlin's stable ordering for ties.
        let utxos = (funds?.outputs ?? [])
            .filter { $0.status == filter }
            .enumerated()
            .sorted { a, b in
                let ka = a.element.blockheight ?? UInt32.max
                let kb = b.element.blockheight ?? UInt32.max
                if ka != kb { return ka > kb }
                return a.offset < b.offset
            }
            .map(\.element)

        VStack(alignment: .leading, spacing: 0) {
            Text("UTXOs")
                .font(Tokens.spaceGrotesk(24, .bold))
                .foregroundStyle(Tokens.Text)
                .padding(.top, 6)
                .padding(.bottom, 4)
            Text("On-chain outputs")
                .font(Tokens.manrope(12))
                .foregroundStyle(Tokens.Faint)
                .padding(.bottom, 14)

            FlowLayout(spacing: 8) {
                ForEach(FILTERS, id: \.self) { f in
                    let on = filter == f
                    Text(capitalizeFirst(f))
                        .font(Tokens.manrope(12.5, .bold))
                        .foregroundStyle(on ? Tokens.Accent : Tokens.Dim)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(on ? Tokens.Accent.opacity(0.1) : Tokens.Card, in: Capsule())
                        .overlay(
                            Capsule().strokeBorder(
                                on ? Tokens.Accent.opacity(0.4) : Tokens.BorderSoft,
                                lineWidth: 1
                            )
                        )
                        .contentShape(Capsule())
                        .onTapGesture { filter = f }
                }
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(utxos, id: \.utxoKey) { u in
                        UtxoRow(u: u, unit: unit) {
                            // Address page shows the UTXO's full life; fall
                            // back to the funding tx when the node reports no
                            // address (same comment and logic as Kotlin).
                            let path = u.address.map { "address/\($0)" } ?? "tx/\(u.txid)"
                            openMempool(openURL, path: path)
                        }
                    }
                    if utxos.isEmpty {
                        Text(funds == nil ? "Loading…" : "No \(filter) outputs")
                            .font(Tokens.manrope(12.5))
                            .foregroundStyle(Tokens.Faint)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 36)
                    }
                }
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await repository.refreshFunds().value
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Kotlin: LaunchedEffect(connState) { if (node != null && funds ==
        // null) refreshFunds() } — re-fires on every connection change.
        .task(id: repository.connState) {
            repository.fetchIfNeeded(.funds)
        }
    }
}

// MARK: - Row

private struct UtxoRow: View {
    let u: OnchainOutput
    let unit: DisplayUnit
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 12) {
                RowIcon(bg: Tokens.Accent.opacity(0.07)) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.Accent)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(u.txid.prefix(6))…\(u.txid.suffix(5)):\(u.output)")
                        .font(Tokens.jetBrainsMono(14.5, .semibold))
                        .foregroundStyle(Tokens.Text)
                    Text(u.address ?? "—")
                        .font(Tokens.jetBrainsMono(12.5))
                        .foregroundStyle(Tokens.Dim)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 3) {
                    Text(formatAmount(msat: u.amountMsat, unit: unit))
                        .font(Tokens.spaceGrotesk(15, .semibold))
                        .foregroundStyle(Tokens.Text)
                    Text(capitalizeFirst(u.status))
                        .font(Tokens.manrope(11.5, .heavy))
                        .foregroundStyle(utxoStatusColor(u.status))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(Tokens.Card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Tokens.BorderSoft, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow layout

/// Minimal left-to-right wrapping layout — the SwiftUI stand-in for Compose's
/// `FlowRow` used by the filter chips (equal 8pt gaps both axes).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width
            usedWidth = max(usedWidth, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? usedWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
