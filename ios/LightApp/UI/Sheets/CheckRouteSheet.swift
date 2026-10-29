//
//  CheckRouteSheet.swift
//  LightApp
//
//  askrene getroutes dry-run: pick a source (our node or a custom id),
//  destination, amount/CLTV, fee/delay budgets and layers, then render the
//  resulting parts with per-hop fees. Port of CheckRouteSheet in
//  android/src/main/java/app/light/wallet/ui/sheets/SheetHost.kt.
//

import SwiftUI

@MainActor
struct CheckRouteSheet: View {
    let repository: WalletRepository
    let onClose: () -> Void

    @State private var selfSource = true
    @State private var source = ""
    @State private var dest = ""
    // Defaults mirror the design's prefills (converted into the display unit).
    @State private var amount: String
    @State private var cltv = "18"
    @State private var maxFee: String
    @State private var maxDelay = "2016"
    @State private var layers: Set<String> = ["auto.localchans", "auto.no_mpp_support"]
    @State private var layerExtra = ""
    @State private var busy = false
    @State private var error: String?
    @State private var result: RoutesResult?

    private static let layerOptions = [
        "auto.localchans", "auto.no_mpp_support", "auto.sourcefree", "xpay",
    ]

    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    init(repository: WalletRepository, onClose: @escaping () -> Void) {
        self.repository = repository
        self.onClose = onClose
        let unit = DisplayUnit.from(stored: repository.displayUnit)
        _amount = State(
            initialValue: formatAmount(msat: 25_000_000, unit: unit)
                .replacingOccurrences(of: " ", with: ""))
        _maxFee = State(
            initialValue: formatAmount(msat: 250_000, unit: unit)
                .replacingOccurrences(of: " ", with: ""))
    }

    private var unit: DisplayUnit { DisplayUnit.from(stored: repository.displayUnit) }
    private var ourId: String? { repository.connState.info?.id }

    private var amountMsat: UInt64? { parseAmountToMsat(amount, unit: unit) }
    private var maxFeeMsat: UInt64? { parseAmountToMsat(maxFee, unit: unit) }

    private var ready: Bool {
        !busy
            && !dest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && amountMsat != nil
            && maxFeeMsat != nil
            && (selfSource || !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetTitle(text: "Check route", onClose: onClose)

            FieldLabel(text: "Source")
            sourceSection

            FieldLabel(text: "Destination", topPadding: 12)
            DesignField(value: $dest, placeholder: "Destination node ID", mono: true, lines: 2)

            amountRow
            budgetRow

            FieldLabel(text: "Layers", topPadding: 12)
            layerChips
            DesignField(
                value: $layerExtra, placeholder: "Custom layer names, comma separated",
                mono: true
            )
            .padding(.top, 8)

            PillButton(
                text: busy ? "Querying askrene…" : "Check route",
                enabled: ready, height: 52
            ) { check() }
                .padding(.top, 14)

            if let error {
                Text(error)
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Red)
                    .padding(.top, 12)
            }
            if let result {
                resultSection(result)
            }
        }
    }

    // MARK: Source

    @ViewBuilder
    private var sourceSection: some View {
        if selfSource {
            HStack(spacing: 0) {
                Text(ourId.map { shortId($0, 14) } ?? "—")
                    .font(Tokens.jetBrainsMono(12.5))
                    .foregroundStyle(Tokens.TextMid)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("This node")
                    .font(Tokens.manrope(11.5, .bold))
                    .foregroundStyle(Tokens.Accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Tokens.Field, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(Color(hex: 0x17FFFFFF), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .onTapGesture { selfSource = false }
        } else {
            DesignField(value: $source, placeholder: "Source node ID", mono: true, lines: 2)
            Text("Use this node")
                .font(Tokens.manrope(11.5, .bold))
                .foregroundStyle(Tokens.Accent)
                .padding(.top, 6)
                .contentShape(Rectangle())
                .onTapGesture {
                    selfSource = true
                    source = ""
                }
        }
    }

    // MARK: Amount / budget rows

    /// Amount field callback runs the same filter as Android's `onValueChange`.
    private var amountBinding: Binding<String> {
        Binding(get: { amount }, set: { amount = filterAmountInput($0, unit: unit) })
    }

    private var maxFeeBinding: Binding<String> {
        Binding(get: { maxFee }, set: { maxFee = filterAmountInput($0, unit: unit) })
    }

    private var cltvBinding: Binding<String> {
        Binding(get: { cltv }, set: { cltv = $0.filter { "0123456789".contains($0) } })
    }

    private var maxDelayBinding: Binding<String> {
        Binding(get: { maxDelay }, set: { maxDelay = $0.filter { "0123456789".contains($0) } })
    }

    private var amountRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                FieldLabel(text: "Amount (\(unit.label))", topPadding: 0)
                DesignField(value: amountBinding, placeholder: "0", numeric: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                FieldLabel(text: "Final CLTV", topPadding: 0)
                DesignField(value: cltvBinding, placeholder: "18", numeric: true)
            }
            .frame(width: 118)
        }
        .padding(.top, 12)
    }

    private var budgetRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                FieldLabel(text: "Max fee (\(unit.label))", topPadding: 0)
                DesignField(value: maxFeeBinding, placeholder: "0", numeric: true)
            }
            VStack(alignment: .leading, spacing: 0) {
                FieldLabel(text: "Max delay", topPadding: 0)
                DesignField(value: maxDelayBinding, placeholder: "2016", numeric: true)
            }
            .frame(width: 118)
        }
        .padding(.top, 12)
    }

    // MARK: Layers

    private var layerChips: some View {
        LayerFlowLayout(spacing: 8) {
            ForEach(Self.layerOptions, id: \.self) { l in
                let on = layers.contains(l)
                Text(l)
                    .font(Tokens.jetBrainsMono(12.5, .bold))
                    .foregroundStyle(on ? Tokens.Accent : Tokens.Dim)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .background(on ? Tokens.Accent.opacity(0.08) : Color.clear, in: Capsule())
                    .overlay(
                        Capsule().strokeBorder(
                            on ? Tokens.Accent.opacity(0.4) : Color(hex: 0x17FFFFFF),
                            lineWidth: 1
                        )
                    )
                    .contentShape(Capsule())
                    .onTapGesture {
                        if on { layers.remove(l) } else { layers.insert(l) }
                    }
            }
        }
    }

    // MARK: getroutes

    private func check() {
        busy = true
        error = nil
        result = nil
        let selectedLayers = Self.layerOptions.filter { layers.contains($0) }
            + layerExtra.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        let params = GetRoutesParams(
            source: selfSource ? nil : source.trimmingCharacters(in: .whitespacesAndNewlines),
            destination: dest.trimmingCharacters(in: .whitespacesAndNewlines),
            amountMsat: amountMsat ?? 0,
            layers: selectedLayers,
            maxfeeMsat: maxFeeMsat ?? 0,
            finalCltv: UInt32(cltv),
            maxdelay: UInt32(maxDelay)
        )
        Task {
            do {
                result = try await repository.requireNode().getRoutes(params: params)
            } catch {
                if case CoreError.Msg(let message) = error, !message.isEmpty {
                    self.error = message
                } else {
                    let d = (error as NSError).localizedDescription
                    self.error = d.isEmpty ? "getroutes failed" : d
                }
            }
            busy = false
        }
    }

    // MARK: Result

    @ViewBuilder
    private func resultSection(_ r: RoutesResult) -> some View {
        let requested = amountMsat ?? 0
        let sent = r.routes.reduce(UInt64(0)) { acc, rt in
            acc + (rt.path.first?.amountMsat ?? rt.amountMsat)
        }
        let fee = sent > requested ? sent - requested : 0
        let probability = String(
            format: "%.0f", locale: Self.posixLocale, Double(r.probabilityPpm) / 10_000.0)

        HStack(alignment: .bottom, spacing: 0) {
            Text("\(r.routes.count) part\(r.routes.count == 1 ? "" : "s") found · probability \(probability)%")
                .font(Tokens.manrope(12.5, .bold))
                .foregroundStyle(Tokens.Label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(formatAmountFull(msat: fee, unit: unit) + " fee")
                .font(Tokens.jetBrainsMono(13))
                .foregroundStyle(Tokens.Accent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 4)

        ForEach(Array(r.routes.enumerated()), id: \.offset) { i, rt in
            partCard(index: i, route: rt)
        }
    }

    private func partCard(index: Int, route rt: Route) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Part \(index + 1)")
                    .font(Tokens.jetBrainsMono(12, .bold))
                    .foregroundStyle(Tokens.Accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(Tokens.Accent.opacity(0.08), in: Capsule())
                Text("\(rt.path.count) hop\(rt.path.count == 1 ? "" : "s") · delay \(rt.path.first?.delay ?? 0)")
                    .font(Tokens.manrope(12.5))
                    .foregroundStyle(Tokens.Dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(formatAmount(msat: rt.amountMsat, unit: unit))
                    .font(Tokens.spaceGrotesk(13.5, .semibold))
                    .foregroundStyle(Tokens.Text)
            }
            ForEach(Array(rt.path.enumerated()), id: \.offset) { hi, hop in
                // Fee at this hop = its incoming amount minus the next hop's;
                // the final hop delivers, so its fee is 0.
                let next = hi + 1 < rt.path.count ? rt.path[hi + 1].amountMsat : hop.amountMsat
                let hopFee = hop.amountMsat > next ? hop.amountMsat - next : 0
                HStack(spacing: 10) {
                    Text("\(hi + 1)")
                        .font(Tokens.jetBrainsMono(11, .semibold))
                        .foregroundStyle(Tokens.Faint)
                        .frame(width: 22, alignment: .leading)
                    Text(hop.shortChannelIdDir ?? shortId(hop.nextNodeId, 8))
                        .font(Tokens.jetBrainsMono(12))
                        .foregroundStyle(Tokens.TextMid)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(formatAmountFull(msat: hopFee, unit: unit))
                        .font(Tokens.manrope(12))
                        .foregroundStyle(Tokens.Dim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Tokens.Field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Tokens.Border, lineWidth: 1)
        )
        .padding(.top, 10)
    }
}

// MARK: - Flow layout

/// Left-aligned wrapping row — the SwiftUI stand-in for Compose's `FlowRow`
/// used by the layer chips (8pt gaps both ways).
private struct LayerFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width
            width = max(width, x)
            x += spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > bounds.width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(
                at: CGPoint(x: bounds.minX + x, y: bounds.minY + y),
                proposal: .unspecified
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
