//
//  AppRoot.swift
//  LightApp
//
//  Root of the wallet UI: onboarding gate, the 6-tab scaffold with a custom
//  bottom bar, the sheet host, the boot pill, and the toast overlay.
//  Port of android/src/main/java/app/light/wallet/ui/AppRoot.kt.
//

import SwiftUI

// MARK: - Tabs

enum Tab: Int, CaseIterable, Hashable {
    case main
    case invoices
    case transactions
    case channels
    case utxos
    case settings

    var label: String {
        switch self {
        case .main: return "Main"
        case .invoices: return "Invoices"
        case .transactions: return "Transactions"
        case .channels: return "Channels"
        case .utxos: return "UTXOs"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol approximations of the Material icons used on Android.
    var icon: String {
        switch self {
        case .main: return "house"                                    // Outlined.Home
        case .invoices: return "doc.plaintext"                        // Outlined.ReceiptLong
        case .transactions: return "arrow.left.arrow.right"           // Outlined.SwapHoriz
        case .channels: return "point.3.connected.trianglepath.dotted" // Outlined.Hub
        case .utxos: return "cube.transparent"                        // Outlined.ViewInAr
        case .settings: return "gearshape"                            // Outlined.Settings
        }
    }
}

// MARK: - Cross-tab navigation requests

/// (token, segment): asks the Invoices tab to select a segment. The token
/// increments on every request so repeat taps retrigger the tab's
/// `.onChange` even when the segment value is the same — the Swift port of
/// Android's `Pair<Int, Int>` counter mechanism.
struct SegmentRequest: Equatable {
    var token: Int = 0
    var segment: Int = 0
}

/// (token, txid): asks the Transactions tab to expand one card.
struct TxExpandRequest: Equatable {
    var token: Int = 0
    var txid: String? = nil
}

// MARK: - AppRoot

@MainActor
struct AppRoot: View {
    let repository: WalletRepository

    @State private var onboarded: Bool
    @State private var tab: Tab = .main
    @State private var sheet: WalletSheet? = nil
    @State private var invoicesSegmentRequest = SegmentRequest()
    @State private var txExpandRequest = TxExpandRequest()

    init(repository: WalletRepository) {
        self.repository = repository
        _onboarded = State(initialValue: repository.hasWallet())
    }

    var body: some View {
        if !onboarded {
            OnboardingFlow(repository: repository, onDone: {
                onboarded = true
                repository.connectInBackground()
            })
        } else {
            walletScaffold
        }
    }

    // MARK: Scaffold

    private var hasPending: Bool {
        repository.activePayments.contains {
            $0.status == .PAYING || $0.status == .PENDING
        }
    }

    private var walletScaffold: some View {
        ZStack {
            Tokens.Bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    currentTab
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.11), value: tab)

                TabBar(current: tab, hasPending: hasPending) { tab = $0 }
            }

            // Boot pill: floating status while the node is being scheduled.
            if case .connecting = repository.connState {
                bootPill
            }

            // Design toast pill (white, bottom-centered, auto-dismiss).
            ToastOverlay()
        }
        .sheet(item: $sheet) { s in
            SheetHost(
                repository: repository,
                sheet: s,
                onClose: { sheet = nil },
                onOpenSheet: { sheet = $0 },
                onWalletWiped: {
                    sheet = nil
                    onboarded = false
                },
                onPaymentStarted: { id in
                    // Design flow: land on Invoices -> Payments with the live
                    // payment detail sheet on top.
                    tab = .invoices
                    invoicesSegmentRequest = SegmentRequest(
                        token: invoicesSegmentRequest.token + 1, segment: 1)
                    sheet = .activePaymentDetail(paymentId: id)
                }
            )
        }
    }

    // MARK: Tab content

    /// One tab alive at a time (matching Android's AnimatedContent), switched
    /// with a fast ~110 ms crossfade.
    @ViewBuilder
    private var currentTab: some View {
        switch tab {
        case .main:
            MainTab(
                repository: repository,
                onOpenSheet: { sheet = $0 },
                onGoTransactions: { tab = .transactions },
                onRecentInvoice: { inv in
                    openInvoicesAt(segment: 0, detail: .invoiceDetail(inv))
                },
                onRecentPay: { p in
                    openInvoicesAt(segment: 1, detail: .paymentDetail(p))
                },
                onRecentTx: { txid in
                    openTransactionExpanded(txid: txid)
                }
            )
        case .invoices:
            InvoicesTab(
                repository: repository,
                onOpenSheet: { sheet = $0 },
                segmentRequest: invoicesSegmentRequest
            )
        case .transactions:
            TransactionsTab(
                repository: repository,
                expandRequest: txExpandRequest
            )
        case .channels:
            ChannelsTab(
                repository: repository,
                onOpenSheet: { sheet = $0 }
            )
        case .utxos:
            UtxoTab(repository: repository)
        case .settings:
            SettingsTab(
                repository: repository,
                onOpenSheet: { sheet = $0 },
                onWalletWiped: { onboarded = false }
            )
        }
    }

    // MARK: Cross-tab navigation

    private func openInvoicesAt(segment: Int, detail: WalletSheet?) {
        tab = .invoices
        invoicesSegmentRequest = SegmentRequest(
            token: invoicesSegmentRequest.token + 1, segment: segment)
        if let detail { sheet = detail }
    }

    private func openTransactionExpanded(txid: String) {
        tab = .transactions
        txExpandRequest = TxExpandRequest(
            token: txExpandRequest.token + 1, txid: txid)
    }

    // MARK: Boot pill

    private var bootPill: some View {
        HStack(spacing: 9) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Tokens.Accent)
                .scaleEffect(0.65)
                .frame(width: 13, height: 13)
            Text("Contacting Greenlight scheduler…")
                .font(Tokens.manrope(12, .bold))
                .foregroundStyle(Tokens.TextMid)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(hex: 0xF210181E), in: Capsule())
        .overlay(Capsule().strokeBorder(Tokens.Accent.opacity(0.3), lineWidth: 1))
        .padding(.top, 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Tab bar

private struct TabBar: View {
    let current: Tab
    let hasPending: Bool
    let onPick: (Tab) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { t in
                let color = t == current ? Tokens.Accent : Tokens.Faint
                Button {
                    onPick(t)
                } label: {
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: t.icon)
                                .font(.system(size: 18, weight: .regular))
                                .frame(width: 21, height: 21)
                                .foregroundStyle(color)
                            if t == .invoices && hasPending {
                                Circle()
                                    .fill(Tokens.Orange)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 3, y: -2)
                            }
                        }
                        // Design is 9.5pt; the longest label ("Transactions")
                        // takes one step down to survive narrow screens with
                        // 6 tabs.
                        Text(t.label)
                            .font(Tokens.manrope(t.label.count > 10 ? 9 : 9.5, .medium))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundStyle(color)
                    }
                    .padding(.top, 6)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .background {
            Tokens.Sheet.opacity(0.95).ignoresSafeArea(edges: .bottom)
        }
    }
}
