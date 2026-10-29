import SwiftUI
import UIKit
import CoreImage
import Observation
import UniformTypeIdentifiers

// Shared component library — ported one-for-one from
// android/src/main/java/app/light/wallet/ui/Components.kt (plus the small
// private helpers the Android screens re-declare: GhostButton, FieldLabel,
// DesignField, QrBox/QrView, SectionLabel, Empty).
// Reference visuals: design/lightning-wallet.dc.html.
//
// Compose-only helpers that have no iOS equivalent here:
//  - Modifier.noRipple   → SwiftUI buttons use the plain styles below (no ink splash).
//  - PullRefreshBox      → screens use the native `.refreshable {}` modifier.
//  - autoRefreshTick     → screens use `.task { while … try await Task.sleep }`.
//  - SecureScreen        → see `PrivacyCover` at the bottom of this file.

// ─────────────────────────── Bolt glyph ───────────────────────────

/// The design's lightning bolt: polygon 11,1 4,11.5 8.6,11.5 7.4,19 16,8.5 10.9,8.5
/// in a 20×20 viewBox (design HTML, `icon('bolt')`).
struct BoltShape: Shape {
    func path(in rect: CGRect) -> Path {
        let pts: [(CGFloat, CGFloat)] = [
            (11, 1), (4, 11.5), (8.6, 11.5), (7.4, 19), (16, 8.5), (10.9, 8.5),
        ]
        var path = Path()
        let scaled = pts.map { p in
            CGPoint(x: rect.minX + p.0 / 20 * rect.width,
                    y: rect.minY + p.1 / 20 * rect.height)
        }
        path.move(to: scaled[0])
        for p in scaled.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
}

/// Convenience filled bolt at a given point size.
struct BoltIcon: View {
    var size: CGFloat = 14
    var color: Color = Tokens.Accent

    var body: some View {
        BoltShape()
            .fill(color)
            .frame(width: size, height: size)
    }
}

// ─────────────────────────── Button styles ───────────────────────────

/// Subtle pressed feedback for the outline/ghost/soft pills — the design has
/// its own pressed states and no ink splash (Android's `noRipple`).
private struct PressFadeStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

private struct PillFillStyle: ButtonStyle {
    let enabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                enabled
                    ? (configuration.isPressed ? Tokens.AccentHi : Tokens.Accent)
                    : Tokens.Accent.opacity(0.3),
                in: Capsule()
            )
    }
}

// ─────────────────────────── Pills ───────────────────────────

/// Filled yellow pill — the design's primary CTA. `bolt: true` prepends the
/// lightning glyph like the design's "Pay" button.
struct PillButton: View {
    let text: String
    var enabled: Bool = true
    var height: CGFloat = 52
    var bolt: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if bolt { BoltIcon(size: 14, color: Tokens.AccentInk) }
                Text(text)
                    .font(Tokens.manrope(15, .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(Tokens.AccentInk)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(PillFillStyle(enabled: enabled))
        .disabled(!enabled)
    }
}

/// Neutral bordered pill (onboarding's secondary "Restore wallet" action).
struct GhostButton: View {
    let text: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Tokens.manrope(15, .bold))
                .foregroundStyle(Tokens.TextMid)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .overlay(Capsule().strokeBorder(Color(hex: 0x24FFFFFF), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressFadeStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.5)
    }
}

/// Border-only yellow pill (design's Copy/Generate secondary actions).
struct OutlinePillButton: View {
    let text: String
    var height: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Tokens.manrope(14, .bold))
                .foregroundStyle(Tokens.Accent)
                .lineLimit(1)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .overlay(Capsule().strokeBorder(Tokens.Accent.opacity(0.35), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressFadeStyle())
    }
}

/// Translucent tinted pill (design: rgba(250,204,21,.1) + border).
/// `icon` is an SF Symbol name (Android passed an ImageVector).
struct SoftPillButton: View {
    let text: String
    var height: CGFloat = 44
    var color: Color = Tokens.Accent
    var icon: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color)
                }
                Text(text)
                    .font(Tokens.manrope(13.5, .bold))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(color.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(color.opacity(0.25), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressFadeStyle())
    }
}

/// Outlined danger pill.
struct DangerPillButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Tokens.manrope(14, .bold))
                .foregroundStyle(Tokens.Red)
                .lineLimit(1)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .overlay(Capsule().strokeBorder(Tokens.Red.opacity(0.4), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressFadeStyle())
    }
}

// ─────────────────────────── Cards / rows ───────────────────────────

/// Card container (#11171E, hairline border, r14).
struct DesignCard<Content: View>: View {
    var background: Color = Tokens.Card
    var radius: CGFloat = 14
    var borderColor: Color = Tokens.BorderSoft
    var onClick: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        let card = VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
        if let onClick {
            Button(action: onClick) { card }
                .buttonStyle(PressFadeStyle())
        } else {
            card
        }
    }
}

/// Status badge (tiny uppercase pill).
struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text.uppercased())
            .font(Tokens.manrope(12.5, .heavy))
            .kerning(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }
}

/// Maps a status string to its design color — same table as Components.kt.
func statusColor(_ status: String) -> Color {
    switch status.lowercased() {
    case "paid", "complete", "online", "active", "normal": return Tokens.Green
    case "expired", "failed", "offline": return Tokens.Red
    case "pending", "paying", "unpaid", "opening", "confirming": return Tokens.Orange
    default: return Tokens.Dim
    }
}

/// Round icon bubble used in list rows.
struct RowIcon<Content: View>: View {
    let bg: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack { content() }
            .frame(width: 34, height: 34)
            .background(bg, in: Circle())
    }
}

/// ours/theirs liquidity bar: yellow on purple track.
struct LiquidityBar: View {
    let oursMsat: UInt64
    let totalMsat: UInt64
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let pct = totalMsat == 0 ? 0.0 : Double(oursMsat) / Double(totalMsat)
            ZStack(alignment: .leading) {
                Capsule().fill(Tokens.Purple.opacity(0.35))
                Capsule()
                    .fill(Tokens.Accent)
                    .frame(width: geo.size.width * min(max(pct, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// Big numeral in Space Grotesk with a small dim unit suffix.
struct BalanceText: View {
    let amount: String
    let unit: String
    var color: Color = Tokens.Text
    var size: CGFloat = 32

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(amount)
                .font(Tokens.spaceGrotesk(size, .semibold))
                .kerning(-0.5)
                .foregroundStyle(color)
                .lineLimit(1)
            Text(" " + unit)
                .font(Tokens.spaceGrotesk(size * 15 / 32))
                .foregroundStyle(Tokens.Dim)
                .padding(.bottom, 4)
        }
    }
}

/// The design's 34×20 pill switch with a white knob.
struct DesignSwitch: View {
    let checked: Bool
    let onToggle: () -> Void

    var body: some View {
        ZStack(alignment: checked ? .trailing : .leading) {
            Capsule().fill(checked ? Tokens.Accent : Color(hex: 0x33FFFFFF))
            Circle()
                .fill(Color.white)
                .frame(width: 16, height: 16)
                .padding(2)
        }
        .frame(width: 34, height: 20)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: checked)
        .onTapGesture(perform: onToggle)
    }
}

// ─────────────────────────── Labels / placeholders ───────────────────────────

/// Small bold label above a form field.
struct FieldLabel: View {
    let text: String
    var topPadding: CGFloat = 4

    var body: some View {
        Text(text)
            .font(Tokens.manrope(11.5, .bold))
            .foregroundStyle(Tokens.Dim)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
    }
}

/// Section header used by Settings.
struct SectionLabel: View {
    let text: String
    var topPadding: CGFloat = 4

    var body: some View {
        Text(text)
            .font(Tokens.manrope(12.5, .bold))
            .foregroundStyle(Tokens.Label)
            .padding(.top, topPadding)
            .padding(.bottom, 8)
            .padding(.leading, 2)
    }
}

/// Empty-list placeholder.
struct Empty: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Tokens.manrope(12.5))
            .foregroundStyle(Tokens.Faint)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
    }
}

// ─────────────────────────── Form field ───────────────────────────

/// Dark form field (CardDeep, r13, hairline border, accent border on focus).
/// `numeric` switches to the decimal pad; `lines > 1` grows vertically like
/// the Android `minLines`/`maxLines` pair.
struct DesignField: View {
    @Binding var value: String
    let placeholder: String
    var mono: Bool = false
    var numeric: Bool = false
    var big: Bool = false
    var lines: Int = 1

    @FocusState private var focused: Bool

    private var font: Font {
        if big { return Tokens.spaceGrotesk(20, .semibold) }
        if mono { return Tokens.jetBrainsMono(12) }
        return Tokens.manrope(14)
    }

    private var textColor: Color {
        mono && !big ? Tokens.TextMid : Tokens.Text
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if value.isEmpty {
                Text(placeholder)
                    .font(font)
                    .foregroundStyle(Tokens.Faint)
                    .lineLimit(1)
                    .allowsHitTesting(false)
            }
            Group {
                if lines > 1 {
                    TextField("", text: $value, axis: .vertical)
                        .lineLimit(lines...(lines + 1))
                } else {
                    TextField("", text: $value)
                }
            }
            .font(font)
            .foregroundStyle(textColor)
            .lineSpacing(mono ? 4 : 0)
            .tint(Tokens.Accent)
            .keyboardType(numeric ? .decimalPad : .default)
            .autocorrectionDisabled(mono || numeric || big)
            .textInputAutocapitalization((mono || numeric || big) ? .never : .sentences)
            .focused($focused)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Tokens.CardDeep, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(focused ? Tokens.Accent : Color(hex: 0x17FFFFFF), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .onTapGesture { focused = true }
    }
}

// ─────────────────────────── Key-value panel ───────────────────────────

/// Key-value panel used by every detail sheet. Values are always monospace
/// (design); rows flagged copyable get a copy icon and tap-to-copy.
struct KvPanel: View {
    let rows: [(String, String, Bool)]
    var valueColor: (String) -> Color = { _ in Tokens.TextMid }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                let (k, v, copyable) = row
                Group {
                    if copyable {
                        Button { copyToClipboard(label: k, value: v) } label: { rowBody(k, v, copyable: true) }
                            .buttonStyle(PressFadeStyle())
                    } else {
                        rowBody(k, v, copyable: false)
                    }
                }
                if i != rows.count - 1 {
                    Rectangle()
                        .fill(Color(hex: 0x0AFFFFFF))
                        .frame(height: 1)
                }
            }
        }
        .background(Tokens.CardDeep, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Tokens.Border.opacity(0.5), lineWidth: 1)
        )
    }

    private func rowBody(_ k: String, _ v: String, copyable: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(k)
                .font(Tokens.manrope(12.5, .bold))
                .foregroundStyle(Tokens.Faint)
                .frame(width: 104, alignment: .leading)
                .padding(.top, 1)
            Text(v)
                .font(Tokens.jetBrainsMono(13, .semibold))
                .foregroundStyle(valueColor(k))
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
            if copyable {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.Faint)
                    .padding(.top, 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

// ─────────────────────────── Feerate chips ───────────────────────────

/// slow / normal / urgent selector cards (send + open channel sheets).
struct FeerateChips: View {
    @Binding var selected: String

    private static let options: [(String, String)] = [
        ("slow", "~1 day"), ("normal", "~1 hour"), ("urgent", "next block"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.options, id: \.0) { value, sub in
                let on = selected == value
                VStack(spacing: 2) {
                    Text(value)
                        .font(Tokens.manrope(12.5, .bold))
                        .foregroundStyle(on ? Tokens.Accent : Tokens.TextMid)
                    Text(sub)
                        .font(Tokens.manrope(10.5))
                        .foregroundStyle(Tokens.Faint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    on ? Tokens.Accent.opacity(0.1) : Tokens.CardDeep,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(on ? Tokens.Accent.opacity(0.4) : Color(hex: 0x17FFFFFF), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .onTapGesture { selected = value }
            }
        }
    }
}

// ─────────────────────────── Seed grid ───────────────────────────

/// Numbered 2-column BIP39 word grid. Until `revealed`, words are masked and
/// a tap anywhere reveals them.
struct SeedGrid: View {
    let words: [String]
    let revealed: Bool
    let onReveal: () -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 10) {
                ForEach(0..<((words.count + 1) / 2), id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(0..<2, id: \.self) { col in
                            let idx = row * 2 + col
                            if idx < words.count {
                                cell(idx)
                            } else {
                                Color.clear.frame(maxWidth: .infinity).frame(height: 1)
                            }
                        }
                    }
                }
            }
            if !revealed {
                Text("Tap to reveal")
                    .font(Tokens.manrope(13, .bold))
                    .foregroundStyle(Tokens.Accent)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Color(hex: 0xD90A0E12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Tokens.Accent.opacity(0.4), lineWidth: 1))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !revealed { onReveal() } }
    }

    private func cell(_ idx: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(idx + 1)")
                .font(Tokens.jetBrainsMono(12.5, .semibold))
                .foregroundStyle(Tokens.Faint)
            Text(revealed ? words[idx] : "••••••")
                .font(Tokens.jetBrainsMono(14, .semibold))
                .foregroundStyle(revealed ? Tokens.Text : Tokens.Faint)
                .lineLimit(1)
                // Keep the words out of the accessibility tree so a rogue
                // a11y client can't read the seed (mirrors clearAndSetSemantics).
                .accessibilityHidden(true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Tokens.Field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color(hex: 0x0FFFFFFF), lineWidth: 1)
        )
    }
}

// ─────────────────────────── QR ───────────────────────────

/// QR code on a white rounded card (the quiet zone is the card's padding).
/// Rendered by CoreImage and scaled nearest-neighbor so modules stay crisp.
struct QrView: View {
    let text: String
    var sizePt: CGFloat = 188

    private static let context = CIContext()
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        if let image = Self.qrImage(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(width: sizePt, height: sizePt)
                .padding(12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityLabel("QR")
        }
    }

    private static func qrImage(_ text: String) -> UIImage? {
        if let hit = cache.object(forKey: text as NSString) { return hit }
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage,
              let cg = context.createCGImage(output, from: output.extent) else { return nil }
        let image = UIImage(cgImage: cg)
        cache.setObject(image, forKey: text as NSString)
        return image
    }
}

// ─────────────────────────── Toasts ───────────────────────────

/// In-app toast pill per design (white, bottom-centered, auto-dismiss).
/// Mirrors Android's `Toasts` singleton; `AppRoot` overlays `ToastOverlay`.
@Observable
final class ToastCenter {
    static let shared = ToastCenter()
    private init() {}

    private(set) var toast: (stamp: UUID, text: String)?

    func show(_ text: String) {
        toast = (UUID(), text)
    }

    fileprivate func clear(stamp: UUID) {
        if toast?.stamp == stamp { toast = nil }
    }
}

/// Floating toast pill; place once at the root of `AppRoot`'s ZStack.
struct ToastOverlay: View {
    private let center = ToastCenter.shared

    var body: some View {
        VStack {
            Spacer()
            if let toast = center.toast {
                Text(toast.text)
                    .font(Tokens.manrope(12.5, .bold))
                    .foregroundStyle(Tokens.Bg)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Tokens.Text, in: Capsule())
                    .shadow(color: .black.opacity(0.5), radius: 15, y: 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.stamp) {
                        try? await Task.sleep(for: .seconds(1.8))
                        center.clear(stamp: toast.stamp)
                    }
            }
        }
        .padding(.bottom, 110)
        .animation(.easeOut(duration: 0.25), value: center.toast?.stamp)
        .allowsHitTesting(false)
    }
}

// ─────────────────────────── Clipboard ───────────────────────────

/// Copies `value` and shows the design toast. When `sensitive`, the pasteboard
/// entry is local-only (kept out of Universal Clipboard / Handoff) and expires
/// after 60 s — the iOS analogue of Android's EXTRA_IS_SENSITIVE + delayed clear.
func copyToClipboard(label: String, value: String, sensitive: Bool = false) {
    if sensitive {
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: value]],
            options: [
                .localOnly: true,
                .expirationDate: Date().addingTimeInterval(60),
            ]
        )
        ToastCenter.shared.show("\(label) copied — clears in 60s")
    } else {
        UIPasteboard.general.string = value
        ToastCenter.shared.show("\(label) copied")
    }
}

// ─────────────────────────── Privacy cover ───────────────────────────

/// Full-screen cover shown while the app is not active. This is the iOS
/// stand-in for Android's FLAG_SECURE Recents protection: it blanks the app
/// switcher snapshot so balances/seeds never appear there. iOS provides no
/// API to block screenshots or screen recording of an ordinary view — only
/// the task-switcher snapshot can be protected this way.
struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Tokens.Bg.ignoresSafeArea()
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Tokens.Accent.opacity(0.08))
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Tokens.Accent.opacity(0.25), lineWidth: 1)
                BoltIcon(size: 40, color: Tokens.Accent)
            }
            .frame(width: 88, height: 88)
        }
    }
}

struct PrivacyCoverModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        ZStack {
            content
            if scenePhase != .active {
                PrivacyCover()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: scenePhase == .active)
    }
}

extension View {
    /// Apply at the app root: covers the UI whenever the scene leaves `.active`.
    func privacyCover() -> some View {
        modifier(PrivacyCoverModifier())
    }
}


// MARK: - Keyboard dismissal

/// The two standard iOS answers to "how do I put the keyboard away":
/// dragging the content down dismisses it interactively, and a Done button
/// rides above the keyboard for one-handed dismissal. Apply to every
/// scrollable editing surface (SheetHost chrome, onboarding).
extension View {
    func dismissesKeyboard() -> some View {
        self
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                    .font(Tokens.manrope(15, .bold))
                    .tint(Tokens.Accent)
                }
            }
    }
}
