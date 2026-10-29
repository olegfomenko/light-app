//
//  SheetHost.swift
//  LightApp
//
//  The one modal bottom-sheet container: shared chrome (background, drag
//  indicator, scroll + padding) and the dispatch from `WalletSheet` to the
//  individual sheet views. Port of the ModalBottomSheet host in
//  android/src/main/java/app/light/wallet/ui/sheets/SheetHost.kt.
//
//  Android note that does NOT carry over: the Compose host rebuilt the sheet
//  window with FLAG_SECURE for `WalletSheet.Seed`. iOS has no per-window
//  screenshot flag — the app-root `privacyCover()` blanks the task-switcher
//  snapshot for every screen instead, which is the closest the platform
//  offers.
//

import SwiftUI

@MainActor
struct SheetHost: View {
    let repository: WalletRepository
    let sheet: WalletSheet
    let onClose: () -> Void
    let onOpenSheet: (WalletSheet) -> Void
    let onWalletWiped: () -> Void
    let onPaymentStarted: (Int64) -> Void

    init(
        repository: WalletRepository,
        sheet: WalletSheet,
        onClose: @escaping () -> Void,
        onOpenSheet: @escaping (WalletSheet) -> Void,
        onWalletWiped: @escaping () -> Void,
        onPaymentStarted: @escaping (Int64) -> Void
    ) {
        self.repository = repository
        self.sheet = sheet
        self.onClose = onClose
        self.onOpenSheet = onOpenSheet
        self.onWalletWiped = onWalletWiped
        self.onPaymentStarted = onPaymentStarted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 40)
        }
        .background(Tokens.Sheet)
        // skipPartiallyExpanded = true → one full-height detent.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Tokens.Sheet)
        .dismissesKeyboard()
        // Sheets render in their own UIKit presentation layer ABOVE the app
        // root, so the root privacyCover() cannot blank them in the app
        // switcher — every sheet (the seed sheet especially) needs its own.
        .privacyCover()
    }

    // MARK: Dispatch

    @ViewBuilder
    private var content: some View {
        switch sheet {
        case .receive:
            ReceiveSheet(repository: repository, onClose: onClose)
        case .sendChain:
            SendChainSheet(repository: repository, onClose: onClose)
        case .newInvoice:
            NewInvoiceSheet(repository: repository, onOpenSheet: onOpenSheet, onClose: onClose)
        case .newInvoiceResult(let bolt11, let paymentHash, let expiresAt):
            InvoiceResultSheet(
                bolt11: bolt11, paymentHash: paymentHash, expiresAt: expiresAt, onClose: onClose)
        case .pay(let prefill):
            PaySheet(
                repository: repository, prefill: prefill,
                onPaymentStarted: onPaymentStarted, onClose: onClose)
        case .openChannel:
            OpenChannelSheet(repository: repository, onClose: onClose)
        case .invoiceDetail(let invoice):
            InvoiceDetailSheet(repository: repository, invoice: invoice, onClose: onClose)
        case .paymentDetail(let pay):
            PaymentDetailSheet(repository: repository, pay: pay, onClose: onClose)
        case .activePaymentDetail(let paymentId):
            ActivePaymentSheet(repository: repository, paymentId: paymentId, onClose: onClose)
        case .channelDetail(let channel):
            ChannelDetailSheet(repository: repository, channel: channel, onClose: onClose)
        case .checkRoute:
            CheckRouteSheet(repository: repository, onClose: onClose)
        case .nodeInfoSheet:
            NodeSheet(repository: repository, onClose: onClose)
        case .seed:
            SeedSheet(repository: repository, onClose: onClose)
        case .dropWallet:
            DropSheet(
                repository: repository,
                onCancel: onClose,
                onWiped: {
                    onClose()
                    onWalletWiped()
                })
        }
    }
}

// MARK: - Shared sheet chrome pieces

/// Sheet header row: title (Space Grotesk Bold 19), optional xpay-style badge
/// pill, and an optional ✕ close bubble on the trailing edge.
struct SheetTitle: View {
    let text: String
    var onClose: (() -> Void)? = nil
    var badge: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .font(Tokens.spaceGrotesk(19, .bold))
                .foregroundStyle(Tokens.Text)
                .lineLimit(1)

            if let badge {
                Text(badge)
                    .font(Tokens.jetBrainsMono(11.5, .bold))
                    .foregroundStyle(Tokens.Accent)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .background(Tokens.Accent.opacity(0.08), in: Capsule())
                    .overlay(Capsule().strokeBorder(Tokens.Accent.opacity(0.25), lineWidth: 1))
                    .padding(.leading, 10)
            }

            Spacer(minLength: 8)

            if let onClose {
                Button(action: onClose) {
                    Text("✕")
                        .font(Tokens.manrope(12.5))
                        .foregroundStyle(Tokens.TextMid)
                        .frame(width: 30, height: 30)
                        .background(Color(hex: 0x12FFFFFF), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }
}

/// One row of the Pay sheet's decode preview: dim key on the left, semibold
/// value right-aligned (mono for ids, orange for expiry warnings).
struct DecRow: View {
    let label: String
    let value: String
    var mono: Bool = false
    var orange: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(Tokens.manrope(12))
                .foregroundStyle(Tokens.Faint)
            Text(value)
                .font(mono ? Tokens.jetBrainsMono(12, .semibold) : Tokens.manrope(12, .semibold))
                .foregroundStyle(orange ? Tokens.Orange : Tokens.TextMid)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .multilineTextAlignment(.trailing)
        }
        .frame(maxWidth: .infinity)
    }
}
