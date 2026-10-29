import Foundation

// Ported one-for-one from android/src/main/java/app/light/wallet/ui/Format.kt.
// All formatting is pinned to en_US_POSIX; thousands separator is a space;
// zero always renders "0".

/// Display units supported by Settings.
enum DisplayUnit: CaseIterable {
    case SAT, MSAT, BTC

    var label: String {
        switch self {
        case .SAT: return "sats"
        case .MSAT: return "msat"
        case .BTC: return "BTC"
        }
    }

    /// The string persisted by Settings; inverse of `from(stored:)`.
    var stored: String {
        switch self {
        case .SAT: return "sat"
        case .MSAT: return "msat"
        case .BTC: return "btc"
        }
    }

    static func from(stored: String) -> DisplayUnit {
        switch stored {
        case "btc": return .BTC
        case "msat": return .MSAT
        default: return .SAT
        }
    }
}

private let posixLocale = Locale(identifier: "en_US_POSIX")

/// "%,d" with the comma swapped for a space, as in the Android code.
private func grouped(_ value: UInt64) -> String {
    let digits = Array(String(value))
    guard digits.count > 3 else { return String(digits) }
    var out: [Character] = []
    out.reserveCapacity(digits.count + digits.count / 3)
    for (i, ch) in digits.reversed().enumerated() {
        if i > 0 && i % 3 == 0 { out.append(" ") }
        out.append(ch)
    }
    return String(out.reversed())
}

/// Kotlin's `.trimEnd('0').trimEnd('.')` for fixed-point decimal strings.
private func trimTrailingZeros(_ s: String) -> String {
    var t = s
    while t.hasSuffix("0") { t.removeLast() }
    if t.hasSuffix(".") { t.removeLast() }
    return t
}

func formatAmount(msat: UInt64?, unit: DisplayUnit) -> String {
    guard let msat else { return "—" }
    if msat == 0 { return "0" } // zero is plain 0 in every unit and locale
    switch unit {
    case .SAT:
        return grouped(msat / 1000)
    case .MSAT:
        return grouped(msat)
    case .BTC:
        return trimTrailingZeros(
            String(format: "%.8f", locale: posixLocale, Double(msat) / 100_000_000_000.0)
        )
    }
}

func formatMsatAsSat(_ msat: UInt64?) -> String {
    guard let msat else { return "—" }
    return grouped(msat / 1000) + " sat"
}

/// Parse an amount the user typed in their display unit into msat.
func parseAmountToMsat(_ input: String, unit: DisplayUnit) -> UInt64? {
    let t = input.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: " ", with: "")
    if t.isEmpty { return nil }
    switch unit {
    case .SAT:
        guard let v = UInt64(t) else { return nil }
        let (msat, overflow) = v.multipliedReportingOverflow(by: 1000)
        return overflow ? nil : msat
    case .MSAT:
        return UInt64(t)
    case .BTC:
        // Exact decimal arithmetic; mirrors the BigDecimal path in Kotlin.
        var body = t
        guard body.allSatisfy({ "0123456789.".contains($0) }) else { return nil }
        guard body.filter({ $0 == "." }).count <= 1 else { return nil }
        if body.hasSuffix(".") { body.removeLast() }   // "5." parses as 5 (Kotlin BigDecimal accepts it)
        if body.hasPrefix(".") { body = "0" + body }   // ".5" is .5
        guard !body.isEmpty, let d = Decimal(string: body, locale: posixLocale) else { return nil }
        let msat = d * Decimal(sign: .plus, exponent: 11, significand: 1) // 1 BTC = 1e11 msat
        var value = msat
        var floored = Decimal()
        NSDecimalRound(&floored, &value, 0, .down)
        guard floored == msat else { return nil }                  // finer than 1 msat
        guard msat <= Decimal(UInt64(Int64.max)) else { return nil } // bitLength > 63
        return UInt64(NSDecimalNumber(decimal: msat).stringValue)
    }
}

/// Input filter for an amount field: digits, plus a single dot in BTC mode.
func filterAmountInput(_ s: String, unit: DisplayUnit) -> String {
    if unit == .BTC {
        let c = s.filter { "0123456789.".contains($0) }
        guard let i = c.firstIndex(of: ".") else { return c }
        let tail = String(c[c.index(after: i)...]).replacingOccurrences(of: ".", with: "")
        return String(c[...i]) + tail
    } else {
        return s.filter { "0123456789".contains($0) }
    }
}

/// Full-precision amount in the user's display unit, label included.
/// Sub-sat precision is never silently dropped: a 312 msat fee shows as
/// "0.312 sats", not "0 sats".
func formatAmountFull(msat: UInt64?, unit: DisplayUnit) -> String {
    guard let msat else { return "—" }
    let value: String
    switch unit {
    case .MSAT:
        value = grouped(msat)
    case .SAT:
        let whole = grouped(msat / 1000)
        let rem = msat % 1000
        if rem == 0 {
            value = whole
        } else {
            var frac = String(format: "%03d", locale: posixLocale, Int(rem))
            while frac.hasSuffix("0") { frac.removeLast() }
            value = whole + "." + frac
        }
    case .BTC:
        value = trimTrailingZeros(
            String(format: "%.11f", locale: posixLocale, Double(msat) / 100_000_000_000.0)
        )
    }
    return "\(value) \(unit.label)"
}

func satsToBtcLine(_ msat: UInt64?) -> String {
    guard let msat else { return "" }
    return String(format: "%.8f", locale: posixLocale, Double(msat) / 100_000_000_000.0)
}

/// Compact "830k" style used in liquidity labels.
func formatCompactSat(_ msat: UInt64?) -> String {
    guard let msat else { return "—" }
    let sat = msat / 1000
    switch sat {
    case 100_000_000...:
        return String(format: "%.2f BTC", locale: posixLocale, Double(sat) / 100_000_000.0)
    case 1_000_000...:
        return String(format: "%.1fM", locale: posixLocale, Double(sat) / 1_000_000.0)
    case 1_000...:
        return grouped(sat / 1_000) + "k"
    default:
        return String(sat)
    }
}

// DateFormatter construction is expensive; this runs per row in every list.
// Formatting is @MainActor-only in this app, so a shared instance is safe.
private let unixTimeFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.locale = posixLocale
    fmt.dateFormat = "MMM d, HH:mm"
    return fmt
}()

func formatUnixTime(_ seconds: UInt64?) -> String {
    guard let seconds, seconds != 0 else { return "—" }
    return unixTimeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(seconds)))
}

func relativeTime(_ seconds: UInt64?) -> String {
    guard let seconds, seconds != 0 else { return "—" }
    let diff = Int64(Date().timeIntervalSince1970) - Int64(clamping: seconds)
    switch diff {
    case ..<0:
        return formatUnixTime(seconds)
    case ..<60:
        return "just now"
    case ..<3600:
        return "\(diff / 60)m ago"
    case ..<86400:
        return "\(diff / 3600)h ago"
    case ..<(7 * 86400):
        return "\(diff / 86400)d ago"
    default:
        return formatUnixTime(seconds)
    }
}

func expiresIn(_ expiresAt: UInt64?) -> String {
    guard let expiresAt, expiresAt != 0 else { return "—" }
    let diff = Int64(clamping: expiresAt) - Int64(Date().timeIntervalSince1970)
    switch diff {
    case ...0:
        return "expired"
    case ..<3600:
        return "in \(diff / 60) min"
    case ..<86400:
        return "in \(diff / 3600)h"
    default:
        return "in \(diff / 86400)d"
    }
}

func shortId(_ id: String?, _ keep: Int = 10) -> String {
    guard let id, !id.isEmpty else { return "—" }
    if id.count <= keep * 2 { return id }
    return "\(id.prefix(keep))…\(id.suffix(keep))"
}
