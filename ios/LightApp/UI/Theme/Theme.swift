import SwiftUI

// Design tokens — "Bitcoin Lightning Wallet Design" (Lightning Wallet.dc.html).
// Visual direction adapted from "Crypto Wallet App UI Template" by DSCODE.
// Ported one-for-one from android/src/main/java/app/light/wallet/ui/theme/Theme.kt.

extension Color {
    /// 0xAARRGGBB literals, matching Compose's `Color(Long)` values in Theme.kt.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: Double((hex >> 24) & 0xFF) / 255.0
        )
    }
}

enum Tokens {
    static let Bg = Color(hex: 0xFF0A0E12)
    static let Card = Color(hex: 0xFF11171E)          // list rows / cards
    static let CardDeep = Color(hex: 0xFF0D1319)      // inputs / kv panels
    static let Sheet = Color(hex: 0xFF10161D)
    static let Field = Color(hex: 0xFF131A21)
    static let Text = Color(hex: 0xFFEEF3F6)
    static let TextMid = Color(hex: 0xFFB7C2CC)
    static let Dim = Color(hex: 0xFF7E8B99)
    static let Faint = Color(hex: 0xFF5A6673)
    static let Label = Color(hex: 0xFF9FB0BC)
    static let Accent = Color(hex: 0xFFFACC15)
    static let AccentHi = Color(hex: 0xFFFDE047)
    static let AccentInk = Color(hex: 0xFF241A02)
    static let Green = Color(hex: 0xFF34D399)
    static let Red = Color(hex: 0xFFF8716F)
    static let Orange = Color(hex: 0xFFFB923C)
    static let OrangeSoft = Color(hex: 0xFFFDBA74)
    static let Purple = Color(hex: 0xFFA78BFA)
    static let Btc = Color(hex: 0xFFF7931A)
    static let Border = Color(hex: 0x12FFFFFF)        // rgba(255,255,255,.07)
    static let BorderSoft = Color(hex: 0x0DFFFFFF)    // rgba(255,255,255,.05)

    // MARK: Fonts
    //
    // The bundled TTFs are static exports of the variable fonts, so their
    // PostScript names carry the master's name ("Manrope ExtraLight",
    // "Space Grotesk Light"). These are the names verified from the actual
    // files in Resources/Fonts — do not "correct" them to "Manrope-Regular".

    /// Body font — mirrors Android's `Manrope` FontFamily.
    static func manrope(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "ManropeExtraLight-Medium"
        case .semibold: name = "ManropeExtraLight-SemiBold"
        case .bold: name = "ManropeExtraLight-Bold"
        case .heavy, .black: name = "ManropeExtraLight-ExtraBold"
        default: name = "ManropeExtraLight-Regular"
        }
        return Font.custom(name, size: size)
    }

    /// Display font (balance numerals, titles) — mirrors Android's `SpaceGrotesk`.
    /// SemiBold maps to Bold: only Regular/Medium/Bold are registered in Info.plist.
    static func spaceGrotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "SpaceGroteskLight-Medium"
        case .semibold: name = "SpaceGroteskLight-SemiBold"
        case .bold, .heavy, .black: name = "SpaceGroteskLight-Bold"
        default: name = "SpaceGroteskLight-Regular"
        }
        return Font.custom(name, size: size)
    }

    /// Monospace font (ids, invoices, amounts) — mirrors Android's `MonoFont`.
    /// ui-monospace in the design; SF Mono is not redistributable, JetBrains Mono
    /// is the closest open equivalent.
    static func jetBrainsMono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .medium: name = "JetBrainsMono-Medium"
        case .semibold: name = "JetBrainsMono-SemiBold"
        case .bold, .heavy, .black: name = "JetBrainsMono-Bold"
        default: name = "JetBrainsMono-Regular"
        }
        return Font.custom(name, size: size)
    }
}
