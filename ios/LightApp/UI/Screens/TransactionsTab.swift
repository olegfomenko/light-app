//
//  TransactionsTab.swift
//  LightApp
//
//  On-chain transactions list with expandable detail cards.
//  Port of android/src/main/java/app/light/wallet/ui/transactions/TransactionsTab.kt.
//  Visual truth: design/lightning-wallet.dc.html, "TRANSACTIONS TAB" section.
//

import SwiftUI

// MARK: - Helpers (Android: `internal` in the transactions package; UtxoTab
// keeps its own file-private copies on iOS, so these stay private here)

/// Opens a mempool.space path ("tx/<txid>", "address/<addr>") in the browser.
private func openMempool(_ openURL: OpenURLAction, path: String) {
    if let url = URL(string: "https://mempool.space/\(path)") {
        openURL(url)
    }
}

/// Approximate age of a transaction from block heights: the design shows a
/// relative time, and CLN only gives us heights, so assume ~10 min per block.
private func txApproxTime(blockheight: UInt32, tip: UInt32) -> String {
    if blockheight == 0 { return "in mempool" }
    if tip == 0 || tip < blockheight { return "block \(blockheight)" }
    let age = UInt64(tip - blockheight) * 600
    let now = UInt64(Date().timeIntervalSince1970)
    return relativeTime(now >= age ? now - age : 0)
}

/// unconfirmed | confirmed | spent | immature -> design color.
private func utxoStatusColor(_ status: String) -> Color {
    switch status {
    case "confirmed": return Tokens.Green
    case "unconfirmed": return Tokens.Orange
    case "immature": return Tokens.Purple
    default: return Tokens.Faint // spent
    }
}

/// Kotlin `String.replaceFirstChar { it.uppercase() }`.
private func capitalizedFirst(_ s: String) -> String {
    guard let first = s.first else { return s }
    return first.uppercased() + s.dropFirst()
}

/// (txid, vout) key for matching tx inputs/outputs against tracked funds.
private struct Outpoint: Hashable {
    let txid: String
    let vout: UInt32
}

// MARK: - TransactionsTab

struct TransactionsTab: View {
    let repository: WalletRepository
    let expandRequest: TxExpandRequest

    @Environment(\.openURL) private var openURL
    @State private var expandedTx: String? = nil

    init(repository: WalletRepository, expandRequest: TxExpandRequest) {
        self.repository = repository
        self.expandRequest = expandRequest
    }

    /// Outpoint -> tracked output, for matching tx inputs/outputs
    /// (Kotlin: `funds?.outputs?.associateBy { it.txid to it.output }`;
    /// associateBy keeps the last duplicate, hence `uniquingKeysWith`).
    private var tracked: [Outpoint: OnchainOutput] {
        guard let outputs = repository.funds?.outputs else { return [:] }
        return Dictionary(
            outputs.map { (Outpoint(txid: $0.txid, vout: $0.output), $0) },
            uniquingKeysWith: { _, last in last }
        )
    }

    var body: some View {
        let txs = repository.transactions
        let unit = DisplayUnit.from(stored: repository.displayUnit)
        let tip = repository.connState.info?.blockheight ?? 0
        let tracked = self.tracked

        VStack(alignment: .leading, spacing: 0) {
            Text("Transactions")
                .font(Tokens.spaceGrotesk(24, .bold))
                .foregroundStyle(Tokens.Text)
                .padding(.top, 6)
                .padding(.bottom, 4)
            Text("On-chain wallet · \(repository.network)")
                .font(Tokens.manrope(12))
                .foregroundStyle(Tokens.Faint)
                .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // listtransactions returns oldest-first; show newest on top.
                    ForEach(Array((txs ?? []).reversed()), id: \.txid) { tx in
                        TxCard(
                            tx: tx,
                            tracked: tracked,
                            tip: tip,
                            unit: unit,
                            expanded: expandedTx == tx.txid,
                            onToggle: {
                                expandedTx = expandedTx == tx.txid ? nil : tx.txid
                            },
                            onOpen: { path in openMempool(openURL, path: path) }
                        )
                    }
                    if (txs ?? []).isEmpty {
                        Text(txs == nil ? "Loading…" : "No on-chain transactions yet.")
                            .font(Tokens.manrope(12.5))
                            .foregroundStyle(Tokens.Faint)
                            .padding(.top, 24)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await repository.refreshTransactions().value
                await repository.refreshFunds().value
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Cross-tab request: expand the named tx (Kotlin: LaunchedEffect runs
        // on first composition too, hence `initial: true`).
        .onChange(of: expandRequest, initial: true) { _, request in
            if let txid = request.txid { expandedTx = txid }
        }
        // First entry only: fetch if we never loaded; afterwards manual/pull only.
        .onChange(of: repository.connState, initial: true) { _, _ in
            fetchOnEntry()
        }
    }

    private func fetchOnEntry() {
        guard repository.node != nil, repository.transactions == nil else { return }
        repository.fetchIfNeeded(.transactions)
        repository.refreshFunds()
    }
}

// MARK: - Tx card

private struct TxCard: View {
    let tx: WalletTx
    let tracked: [Outpoint: OnchainOutput]
    let tip: UInt32
    let unit: DisplayUnit
    let expanded: Bool
    let onToggle: () -> Void
    let onOpen: (String) -> Void

    var body: some View {
        let ins: [(WalletTxInput, OnchainOutput)] = tx.inputs.compactMap { i in
            tracked[Outpoint(txid: i.txid, vout: i.index)].map { (i, $0) }
        }
        let outs: [(WalletTxOutput, OnchainOutput)] = tx.outputs.compactMap { o in
            tracked[Outpoint(txid: tx.txid, vout: o.index)].map { (o, $0) }
        }
        let netMsat = outs.reduce(Int64(0)) { $0 + Int64($1.1.amountMsat) }
            - ins.reduce(Int64(0)) { $0 + Int64($1.1.amountMsat) }
        let confirmed = tx.blockheight > 0
        let conf: UInt32 = (confirmed && tip >= tx.blockheight) ? tip - tx.blockheight + 1 : 0

        VStack(alignment: .leading, spacing: 0) {
            header(netMsat: netMsat, confirmed: confirmed)
            if expanded {
                detail(ins: ins, outs: outs, confirmed: confirmed, conf: conf)
                    .padding(.top, 11)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(expanded ? Tokens.Accent.opacity(0.3) : Tokens.BorderSoft, lineWidth: 1)
        )
    }

    // MARK: Header row

    private func header(netMsat: Int64, confirmed: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(tx.txid.prefix(6))…\(tx.txid.suffix(5))")
                    .font(Tokens.jetBrainsMono(14.5, .semibold))
                    .foregroundStyle(Tokens.Text)
                    .lineLimit(1)
                Text(txApproxTime(blockheight: tx.blockheight, tip: tip))
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 3) {
                Text((netMsat >= 0 ? "+" : "−") + formatAmount(msat: netMsat.magnitude, unit: unit))
                    .font(Tokens.spaceGrotesk(15, .semibold))
                    .foregroundStyle(netMsat >= 0 ? Tokens.Green : Tokens.Text)
                    .lineLimit(1)
                Text(confirmed ? "Confirmed" : "Unconfirmed")
                    .font(Tokens.manrope(11.5, .heavy))
                    .foregroundStyle(confirmed ? Tokens.Green : Tokens.Orange)
            }
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Tokens.Faint)
                .frame(width: 14, height: 14)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
    }

    // MARK: Expanded detail

    private func detail(
        ins: [(WalletTxInput, OnchainOutput)],
        outs: [(WalletTxOutput, OnchainOutput)],
        confirmed: Bool,
        conf: UInt32
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(Color(hex: 0x0DFFFFFF))
                .frame(maxWidth: .infinity)
                .frame(height: 1)

            // TXID row -> mempool
            HStack(alignment: .center, spacing: 8) {
                Text("TXID")
                    .font(Tokens.manrope(11.5, .bold))
                    .foregroundStyle(Tokens.Faint)
                Text(tx.txid)
                    .font(Tokens.jetBrainsMono(12.5))
                    .foregroundStyle(Tokens.TextMid)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.Accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Tokens.CardDeep, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Tokens.Border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .onTapGesture { onOpen("tx/\(tx.txid)") }

            // Confirmations row
            HStack(alignment: .center, spacing: 8) {
                Text("Confirmations")
                    .font(Tokens.manrope(11.5, .bold))
                    .foregroundStyle(Tokens.Faint)
                Text(confirmed ? "\(conf)" : "Unconfirmed")
                    .font(Tokens.jetBrainsMono(12.5))
                    .foregroundStyle(Tokens.TextMid)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Tokens.CardDeep, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Tokens.Border, lineWidth: 1)
            )

            Text("Only inputs and outputs tracked by your CLN node are shown.")
                .font(Tokens.manrope(12))
                .foregroundStyle(Tokens.Dim)
                .lineSpacing(4)

            if !ins.isEmpty {
                Text("Inputs")
                    .font(Tokens.manrope(11.5, .bold))
                    .foregroundStyle(Tokens.Faint)
                ForEach(Array(ins.enumerated()), id: \.offset) { _, pair in
                    let (inp, utxo) = pair
                    IoRow(vout: inp.index, utxo: utxo, unit: unit) {
                        onOpen(utxo.address.map { "address/\($0)" } ?? "tx/\(inp.txid)")
                    }
                }
            }
            if !outs.isEmpty {
                Text("Outputs")
                    .font(Tokens.manrope(11.5, .bold))
                    .foregroundStyle(Tokens.Faint)
                ForEach(Array(outs.enumerated()), id: \.offset) { _, pair in
                    let (out, utxo) = pair
                    IoRow(vout: out.index, utxo: utxo, unit: unit) {
                        onOpen(utxo.address.map { "address/\($0)" } ?? "tx/\(tx.txid)")
                    }
                }
            }
            if ins.isEmpty && outs.isEmpty {
                Text("No tracked inputs or outputs in this transaction.")
                    .font(Tokens.manrope(11.5))
                    .foregroundStyle(Tokens.Faint)
            }
        }
    }
}

// MARK: - Input/output row

private struct IoRow: View {
    let vout: UInt32
    let utxo: OnchainOutput
    let unit: DisplayUnit
    let onClick: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("#\(vout)")
                .font(Tokens.jetBrainsMono(11.5, .semibold))
                .foregroundStyle(Tokens.Faint)
            Text(utxo.address ?? "\(utxo.txid.prefix(8))…")
                .font(Tokens.jetBrainsMono(12.5))
                .foregroundStyle(Tokens.TextMid)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatAmount(msat: utxo.amountMsat, unit: unit))
                    .font(Tokens.spaceGrotesk(13, .semibold))
                    .foregroundStyle(Tokens.Text)
                    .lineLimit(1)
                Text(capitalizedFirst(utxo.status))
                    .font(Tokens.manrope(11, .heavy))
                    .foregroundStyle(utxoStatusColor(utxo.status))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Tokens.CardDeep, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Tokens.Border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture(perform: onClick)
    }
}
