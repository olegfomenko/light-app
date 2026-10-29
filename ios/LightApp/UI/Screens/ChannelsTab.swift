//
//  ChannelsTab.swift
//  LightApp
//
//  Channels list: liquidity summary card + per-channel cards.
//  Port of android/src/main/java/app/light/wallet/ui/channels/ChannelsTab.kt.
//

import SwiftUI

@MainActor
struct ChannelsTab: View {
    let repository: WalletRepository
    let onOpenSheet: (WalletSheet) -> Void

    init(repository: WalletRepository, onOpenSheet: @escaping (WalletSheet) -> Void) {
        self.repository = repository
        self.onOpenSheet = onOpenSheet
    }

    var body: some View {
        let channels = repository.channels ?? []
        let usable = channels.filter { $0.state == "CHANNELD_NORMAL" }
        let outbound = usable.reduce(UInt64(0)) { $0 + ($1.toUsMsat ?? 0) }
        let inbound = usable.reduce(UInt64(0)) { $0 + ($1.toThemMsat ?? 0) }
        let capacity = usable.reduce(UInt64(0)) { $0 + ($1.totalMsat ?? 0) }

        VStack(spacing: 0) {
            // Header: title + "+ Open" accent pill.
            HStack {
                Text("Channels")
                    .font(Tokens.spaceGrotesk(24, .bold))
                    .foregroundStyle(Tokens.Text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    onOpenSheet(.openChannel)
                } label: {
                    Text("+ Open")
                        .font(Tokens.manrope(13, .bold))
                        .foregroundStyle(Tokens.AccentInk)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Tokens.Accent, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            .padding(.bottom, 14)

            summaryCard(outbound: outbound, inbound: inbound, capacity: capacity, count: usable.count)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(Array(channels.enumerated()), id: \.offset) { _, ch in
                        ChannelCard(ch: ch) { onOpenSheet(.channelDetail(ch)) }
                    }
                    if channels.isEmpty {
                        Text("No channels yet. Open one to a well-connected peer to start sending and receiving on Lightning.")
                            .font(Tokens.manrope(12.5))
                            .foregroundStyle(Tokens.Faint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 24)
                    }
                }
                .padding(.top, 14)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await repository.refreshChannels().value
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Kotlin: LaunchedEffect(connState) { if (node != null && channels ==
        // null) refreshChannels() } — re-fires on every connection change.
        .task(id: repository.connState) {
            repository.fetchIfNeeded(.channels)
        }
    }

    // MARK: Liquidity summary card

    private func summaryCard(outbound: UInt64, inbound: UInt64, capacity: UInt64, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Outbound")
                        .font(Tokens.manrope(12.5, .bold))
                        .foregroundStyle(Tokens.Dim)
                    Text(formatCompactSat(outbound))
                        .font(Tokens.spaceGrotesk(20, .semibold))
                        .kerning(-0.5)
                        .foregroundStyle(Tokens.Accent)
                        .padding(.top, 3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Rectangle()
                    .fill(Tokens.Border)
                    .frame(width: 1, height: 44)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Inbound")
                        .font(Tokens.manrope(12.5, .bold))
                        .foregroundStyle(Tokens.Dim)
                    Text(formatCompactSat(inbound))
                        .font(Tokens.spaceGrotesk(20, .semibold))
                        .kerning(-0.5)
                        .foregroundStyle(Tokens.Purple)
                        .padding(.top, 3)
                }
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            LiquidityBar(oursMsat: outbound, totalMsat: outbound + inbound)
                .padding(.top, 14)
            Text("Total capacity \(formatCompactSat(capacity)) across \(count) channels")
                .font(Tokens.manrope(12.5))
                .foregroundStyle(Tokens.Faint)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color(hex: 0xFF141B23), Color(hex: 0xFF10161C)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Tokens.Border, lineWidth: 1)
        )
    }
}

// MARK: - Channel card

private struct ChannelCard: View {
    let ch: PeerChannel
    let onTap: () -> Void

    private var stateLabel: String {
        switch ch.state {
        case "CHANNELD_NORMAL":
            return ch.peerConnected ? "active" : "offline"
        case "CHANNELD_AWAITING_LOCKIN", "DUALOPEND_AWAITING_LOCKIN",
             "OPENINGD", "DUALOPEND_OPEN_INIT":
            return "opening"
        default:
            return "closing"
        }
    }

    private var title: String {
        if let alias = ch.peerAlias,
           !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return alias
        }
        return shortId(ch.peerId, 8)
    }

    var body: some View {
        DesignCard(onClick: onTap) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(title)
                        .font(Tokens.manrope(15, .bold))
                        .foregroundStyle(Tokens.Text)
                        .lineLimit(1)
                    Text(ch.shortChannelId ?? shortId(ch.channelId, 8))
                        .font(Tokens.jetBrainsMono(12.5))
                        .foregroundStyle(Tokens.Dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                StatusBadge(text: stateLabel, color: statusColor(stateLabel))
            }
            LiquidityBar(oursMsat: ch.toUsMsat ?? 0, totalMsat: ch.totalMsat ?? 0, height: 5)
                .padding(.top, 12)
            HStack(spacing: 0) {
                Text("Ours ")
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Dim)
                Text(formatCompactSat(ch.toUsMsat))
                    .font(Tokens.manrope(12.5, .bold))
                    .foregroundStyle(Tokens.Accent)
                Spacer(minLength: 0)
                Text("Theirs ")
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Dim)
                Text(formatCompactSat(ch.toThemMsat))
                    .font(Tokens.manrope(12.5, .bold))
                    .foregroundStyle(Tokens.Purple)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
        }
    }
}
