//
//  WalletSheet.swift
//  LightApp
//
//  Every bottom sheet in the app, mirroring the design's sheet layer.
//  Port of android/src/main/java/app/light/wallet/ui/sheets/WalletSheet.kt.
//

import Foundation

enum WalletSheet: Identifiable, Hashable {
    /// On-chain newaddr + QR.
    case receive
    /// On-chain withdraw.
    case sendChain
    /// Invoice creation.
    case newInvoice
    case newInvoiceResult(bolt11: String, paymentHash: String, expiresAt: UInt64)
    /// xpay.
    case pay(prefill: String)
    case openChannel
    case invoiceDetail(InvoiceEntry)
    case paymentDetail(PayListEntry)
    case activePaymentDetail(paymentId: Int64)
    case channelDetail(PeerChannel)
    /// askrene getroutes dry-run.
    case checkRoute
    case nodeInfoSheet
    case seed
    case dropWallet

    var id: WalletSheet { self }
}
