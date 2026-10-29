//
//  ChannelSheets.swift
//  LightApp
//
//  Channel management: open a new channel (connect → fundchannel) and the
//  channel detail sheet with the close-channel flow.
//  Port of OpenChannelSheet + ChannelDetailSheet from
//  android/src/main/java/app/light/wallet/ui/sheets/SheetHost.kt.
//

import SwiftUI

/// Kotlin `e.message` for sheet-local one-shot RPCs — the core surfaces every
/// failure as `CoreError.Msg`, whose generated description is a reflection
/// dump, so unwrap the message ourselves (same rule as WalletRepository).
private func sheetErrorText(_ error: Error) -> String {
    if case CoreError.Msg(let message) = error, !message.isEmpty { return message }
    let d = (error as NSError).localizedDescription
    return d.isEmpty ? "error" : d
}

// ─────────────────────────── Open channel ───────────────────────────

@MainActor
struct OpenChannelSheet: View {
    let repository: WalletRepository
    let onClose: () -> Void

    @State private var peer = ""
    @State private var amount = ""
    @State private var minconf = ""
    /// Empty = the "normal" default, mirroring Android's `feerate.ifBlank { … }`.
    @State private var feerate = ""
    @State private var announce = true
    @State private var busy = false
    @State private var error: String? = nil
    @State private var result: String? = nil

    init(repository: WalletRepository, onClose: @escaping () -> Void) {
        self.repository = repository
        self.onClose = onClose
    }

    private var unit: DisplayUnit { DisplayUnit.from(stored: repository.displayUnit) }

    var body: some View {
        SheetTitle(text: "Open channel", onClose: onClose)
        if let result {
            success(result)
        } else {
            form
        }
    }

    // MARK: Success

    @ViewBuilder
    private func success(_ result: String) -> some View {
        Text("Channel funding broadcast ✓")
            .font(Tokens.spaceGrotesk(15, .bold))
            .foregroundStyle(Tokens.Green)
        Text(result)
            .font(Tokens.jetBrainsMono(12.5))
            .foregroundStyle(Tokens.Dim)
            .padding(.top, 8)
            .padding(.bottom, 16)
        PillButton(text: "Done") { onClose() }
    }

    // MARK: Form

    @ViewBuilder
    private var form: some View {
        let unit = self.unit

        FieldLabel(text: "Peer connect string")
        DesignField(value: $peer, placeholder: "nodeid@host:port", mono: true, lines: 2)

        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Amount (\(unit.label))")
                    .font(Tokens.manrope(11.5, .bold))
                    .foregroundStyle(Tokens.Dim)
                DesignField(
                    value: Binding(
                        get: { amount },
                        set: { amount = filterAmountInput($0, unit: unit) }
                    ),
                    placeholder: {
                        switch unit {
                        case .SAT: return "1 000 000"
                        case .MSAT: return "1 000 000 000"
                        case .BTC: return "0.01"
                        }
                    }(),
                    numeric: true,
                    big: true
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                Text("Min conf")
                    .font(Tokens.manrope(11.5, .bold))
                    .foregroundStyle(Tokens.Dim)
                DesignField(
                    value: Binding(
                        get: { minconf },
                        set: { minconf = $0.filter { c in c.isNumber } }
                    ),
                    placeholder: "1",
                    numeric: true
                )
            }
            .frame(width: 110)
        }
        .padding(.top, 12)

        FieldLabel(text: "Feerate", topPadding: 12)
        FeerateChips(selected: Binding(
            get: { feerate.isEmpty ? "normal" : feerate },
            set: { feerate = $0 }
        ))

        HStack(spacing: 10) {
            DesignSwitch(checked: announce) { announce.toggle() }
            Text("Announce")
                .font(Tokens.manrope(12.5, .bold))
                .foregroundStyle(Tokens.TextMid)
            Text("public channel, visible in gossip")
                .font(Tokens.manrope(11))
                .foregroundStyle(Tokens.Faint)
        }
        .padding(.top, 12)
        .contentShape(Rectangle())
        .onTapGesture { announce.toggle() }

        if let error {
            Text(error)
                .font(Tokens.manrope(12.5))
                .foregroundStyle(Tokens.Red)
                .padding(.top, 10)
        }

        PillButton(
            text: busy ? "Opening…" : "Connect & fund channel",
            enabled: !busy
                && !peer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && parseAmountToMsat(amount, unit: unit) != nil
        ) { open() }
            .padding(.top, 18)

        Text("connect → fundchannel")
            .font(Tokens.jetBrainsMono(11))
            .foregroundStyle(Tokens.Faint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
    }

    // MARK: connect → fundchannel

    private func open() {
        let unit = self.unit
        busy = true
        error = nil
        Task { @MainActor in
            do {
                let node = try repository.requireNode()
                let trimmed = peer.trimmingCharacters(in: .whitespacesAndNewlines)
                let nodeId: String
                if trimmed.contains("@") {
                    // Kotlin: split("@", limit = 2), substringBeforeLast /
                    // substringAfterLast on the host:port half.
                    let parts = trimmed.split(
                        separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
                    let id = String(parts[0])
                    let hostPort = parts.count > 1 ? String(parts[1]) : ""
                    let host: String
                    let portString: String
                    if let colon = hostPort.range(of: ":", options: .backwards) {
                        host = String(hostPort[..<colon.lowerBound])
                        portString = String(hostPort[colon.upperBound...])
                    } else {
                        // Both Kotlin substring*Last calls return the whole
                        // string when the delimiter is absent.
                        host = hostPort
                        portString = hostPort
                    }
                    let cleanId = id.trimmingCharacters(in: .whitespacesAndNewlines)
                    _ = try await node.connectPeer(
                        id: cleanId, host: host, port: UInt32(portString))
                    nodeId = cleanId
                } else {
                    nodeId = trimmed
                }
                let opened = try await repository.performGuardedRPC { try await node.openChannel(params: OpenChannelParams(
                    peerId: nodeId,
                    // msat -> sat floors, exactly like the Kotlin `/ 1000uL`.
                    amountSat: (parseAmountToMsat(amount, unit: unit) ?? 0) / 1000,
                    all: false,
                    feerate: feerate.isEmpty ? nil : feerate,
                    announce: announce,
                    pushMsat: nil,
                    closeTo: nil,
                    minconf: UInt32(minconf),
                    mindepth: nil,
                    reserveMsat: nil
                )) }
                result = "txid \(opened.txid)"
                repository.refreshAfterChannelAction()
            } catch {
                self.error = sheetErrorText(error)
            }
            busy = false
        }
    }
}

// ─────────────────────────── Channel detail ───────────────────────────

@MainActor
struct ChannelDetailSheet: View {
    let repository: WalletRepository
    let channel: PeerChannel
    let onClose: () -> Void

    @State private var confirmClose = false
    @State private var busy = false
    @State private var error: String? = nil
    @State private var closed: String? = nil

    init(repository: WalletRepository, channel: PeerChannel, onClose: @escaping () -> Void) {
        self.repository = repository
        self.channel = channel
        self.onClose = onClose
    }

    private var unit: DisplayUnit { DisplayUnit.from(stored: repository.displayUnit) }

    private var title: String {
        if let alias = channel.peerAlias,
           !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return alias
        }
        return "Channel"
    }

    var body: some View {
        let unit = self.unit

        SheetTitle(text: title, onClose: onClose)

        // Hero: spendable balance over total capacity.
        VStack(spacing: 3) {
            Text("\(formatAmount(msat: channel.spendableMsat, unit: unit)) \(unit.label)")
                .font(Tokens.spaceGrotesk(30, .semibold))
                .kerning(-0.5)
                .foregroundStyle(Tokens.Text)
            Text("spendable of \(formatAmount(msat: channel.totalMsat, unit: unit)) capacity")
                .font(Tokens.manrope(11.5))
                .foregroundStyle(Tokens.Faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 14)

        KvPanel(rows: rows(unit))

        if let closed {
            Text("Close initiated: \(closed)")
                .font(Tokens.manrope(12.5))
                .foregroundStyle(Tokens.Green)
                .padding(.top, 12)
            PillButton(text: "Done") { onClose() }
                .padding(.top, 12)
        } else {
            if let error {
                Text(error)
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Red)
                    .padding(.top, 10)
            }

            DangerPillButton(
                text: busy
                    ? "Closing…"
                    : confirmClose ? "Tap again to confirm close" : "Close channel"
            ) { close() }
                .padding(.top, 14)
        }
    }

    // MARK: Rows

    private func rows(_ unit: DisplayUnit) -> [(String, String, Bool)] {
        let ch = channel
        var rows: [(String, String, Bool)] = [
            ("Peer", ch.peerId, true),
            ("State", ch.state, false),
            ("Connected", ch.peerConnected ? "yes" : "no", false),
        ]
        if let scid = ch.shortChannelId { rows.append(("Short id", scid, true)) }
        rows.append(("Capacity", formatAmountFull(msat: ch.totalMsat, unit: unit), false))
        rows.append(("Ours", formatAmountFull(msat: ch.toUsMsat, unit: unit), false))
        rows.append(("Theirs", formatAmountFull(msat: ch.toThemMsat, unit: unit), false))
        rows.append(("Spendable", formatAmountFull(msat: ch.spendableMsat, unit: unit), false))
        rows.append(("Receivable", formatAmountFull(msat: ch.receivableMsat, unit: unit), false))
        if let reserve = ch.ourReserveMsat {
            rows.append(("Our reserve", formatAmountFull(msat: reserve, unit: unit), false))
        }
        if let feeBase = ch.feeBaseMsat {
            rows.append(("Fee base", formatAmountFull(msat: feeBase, unit: unit), false))
        }
        if let ppm = ch.feeProportionalMillionths {
            rows.append(("Fee ppm", String(ppm), false))
        }
        if let dust = ch.dustLimitMsat {
        }
        if let ours = ch.ourToSelfDelay {
            rows.append(("Our to-self delay", "\(ours) blocks", false))
        }
        if let theirs = ch.theirToSelfDelay {
            rows.append(("Their to-self delay", "\(theirs) blocks", false))
        }
        if let maxHtlcs = ch.maxAcceptedHtlcs {
        }
        if let inFulfilled = ch.inPaymentsFulfilled {
            rows.append((
                "In fulfilled",
                "\(inFulfilled) · \(formatAmountFull(msat: ch.inFulfilledMsat, unit: unit))",
                false
            ))
        }
        if let outFulfilled = ch.outPaymentsFulfilled {
            rows.append((
                "Out fulfilled",
                "\(outFulfilled) · \(formatAmountFull(msat: ch.outFulfilledMsat, unit: unit))",
                false
            ))
        }
        rows.append(("Opener", ch.opener, false))
        if let isPrivate = ch.isPrivate {
        }
        if let funding = ch.fundingTxid { rows.append(("Funding txid", funding, true)) }
        return rows
    }

    // MARK: Close

    private func close() {
        if !confirmClose {
            confirmClose = true
            return
        }
        busy = true
        error = nil
        Task { @MainActor in
            do {
                let node = try repository.requireNode()
                let result = try await repository.performGuardedRPC { try await node.closeChannel(
                    params: CloseChannelParams(
                        id: channel.channelId ?? channel.peerId,
                        unilateralTimeout: nil,
                        destination: nil,
                        feeNegotiationStep: nil,
                        forceLeaseClosed: nil
                    )) }
                closed = result.closeType
                repository.refreshAfterChannelAction()
            } catch {
                self.error = sheetErrorText(error)
            }
            busy = false
        }
    }
}
