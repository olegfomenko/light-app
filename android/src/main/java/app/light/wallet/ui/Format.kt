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

/** Parse an amount the user typed in their display unit into msat. */
fun parseAmountToMsat(input: String, unit: DisplayUnit): ULong? {
    val t = input.trim().replace(" ", "")
    if (t.isEmpty()) return null
    return when (unit) {
        DisplayUnit.SAT -> t.toULongOrNull()?.let { it * 1000uL }
        DisplayUnit.MSAT -> t.toULongOrNull()
        DisplayUnit.BTC -> {
            val d = t.toBigDecimalOrNull() ?: return null
            if (d.signum() < 0) return null
            val msat = d.movePointRight(11) // 1 BTC = 1e11 msat
            if (msat.stripTrailingZeros().scale() > 0) return null // finer than 1 msat
            val bi = msat.toBigInteger()
            if (bi.bitLength() > 63) null else bi.toLong().toULong()
        }
    }
}

/** Input filter for an amount field: digits, plus a single dot in BTC mode. */
fun filterAmountInput(s: String, unit: DisplayUnit): String =
    if (unit == DisplayUnit.BTC) {
        val c = s.filter { it.isDigit() || it == '.' }
        val i = c.indexOf('.')
        if (i == -1) c else c.substring(0, i + 1) + c.substring(i + 1).replace(".", "")
    } else {
        s.filter { it.isDigit() }
    }

/**
 * Full-precision amount in the user's display unit, label included.
 * Sub-sat precision is never silently dropped: a 312 msat fee shows as
 * "0.312 sats", not "0 sats".
 */
fun formatAmountFull(msat: ULong?, unit: DisplayUnit): String {
    if (msat == null) return "—"
    val value = when (unit) {
        DisplayUnit.MSAT ->
            String.format(Locale.US, "%,d", msat.toLong()).replace(',', ' ')
        DisplayUnit.SAT -> {
            val whole = String.format(Locale.US, "%,d", (msat / 1000uL).toLong()).replace(',', ' ')
            val rem = (msat % 1000uL).toLong()
            if (rem == 0L) whole
            else whole + "." + String.format(Locale.US, "%03d", rem).trimEnd('0')
        }
        DisplayUnit.BTC ->
            String.format(Locale.US, "%.11f", msat.toLong() / 100_000_000_000.0)
                .trimEnd('0').trimEnd('.')
    }
    return "$value ${unit.label}"
}

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
