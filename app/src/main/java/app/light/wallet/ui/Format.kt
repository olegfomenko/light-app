package app.light.wallet.ui

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Display units supported by Settings. */
enum class DisplayUnit(val label: String) {
    SAT("sats"), MSAT("msat"), BTC("BTC");

    companion object {
        fun from(stored: String): DisplayUnit = when (stored) {
            "btc" -> BTC
            "msat" -> MSAT
            else -> SAT
        }
    }
}

fun formatAmount(msat: ULong?, unit: DisplayUnit): String {
    if (msat == null) return "—"
    if (msat == 0uL) return "0" // zero is plain 0 in every unit and locale
    return when (unit) {
        DisplayUnit.SAT ->
            String.format(Locale.US, "%,d", (msat / 1000uL).toLong()).replace(',', ' ')
        DisplayUnit.MSAT ->
            String.format(Locale.US, "%,d", msat.toLong()).replace(',', ' ')
        DisplayUnit.BTC ->
            String.format(Locale.US, "%.8f", msat.toLong() / 100_000_000_000.0)
                .trimEnd('0').trimEnd('.')
    }
}

fun formatMsatAsSat(msat: ULong?): String =
    if (msat == null) "—"
    else String.format(Locale.US, "%,d sat", (msat / 1000uL).toLong()).replace(',', ' ')

fun formatMsatFull(msat: ULong?): String =
    if (msat == null) "—"
    else String.format(Locale.US, "%,d msat", msat.toLong()).replace(',', ' ')

fun satsToBtcLine(msat: ULong?): String =
    if (msat == null) "" else String.format(Locale.US, "%.8f", msat.toLong() / 100_000_000_000.0)

/** Compact "830k" style used in liquidity labels. */
fun formatCompactSat(msat: ULong?): String {
    if (msat == null) return "—"
    val sat = (msat / 1000uL).toLong()
    return when {
        sat >= 100_000_000 -> String.format(Locale.US, "%.2f BTC", sat / 100_000_000.0)
        sat >= 1_000_000 -> String.format(Locale.US, "%.1fM", sat / 1_000_000.0)
        sat >= 1_000 -> String.format(Locale.US, "%,dk", sat / 1_000)
        else -> sat.toString()
    }
}

fun formatUnixTime(seconds: ULong?): String {
    if (seconds == null || seconds == 0uL) return "—"
    val fmt = SimpleDateFormat("MMM d, HH:mm", Locale.US)
    return fmt.format(Date(seconds.toLong() * 1000))
}

fun relativeTime(seconds: ULong?): String {
    if (seconds == null || seconds == 0uL) return "—"
    val diff = System.currentTimeMillis() / 1000 - seconds.toLong()
    return when {
        diff < 0 -> formatUnixTime(seconds)
        diff < 60 -> "just now"
        diff < 3600 -> "${diff / 60}m ago"
        diff < 86400 -> "${diff / 3600}h ago"
        diff < 7 * 86400 -> "${diff / 86400}d ago"
        else -> formatUnixTime(seconds)
    }
}

fun expiresIn(expiresAt: ULong?): String {
    if (expiresAt == null || expiresAt == 0uL) return "—"
    val diff = expiresAt.toLong() - System.currentTimeMillis() / 1000
    return when {
        diff <= 0 -> "expired"
        diff < 3600 -> "in ${diff / 60} min"
        diff < 86400 -> "in ${diff / 3600}h"
        else -> "in ${diff / 86400}d"
    }
}

fun shortId(id: String?, keep: Int = 10): String {
    if (id.isNullOrEmpty()) return "—"
    return if (id.length <= keep * 2) id else "${id.take(keep)}…${id.takeLast(keep)}"
}
