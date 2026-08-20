package app.light.wallet.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.ClipDescription
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.ui.theme.MonoFont
import app.light.wallet.ui.theme.SpaceGrotesk
import app.light.wallet.ui.theme.Tokens
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/**
 * Clickable without the default rectangular ripple — the design has its own
 * pressed states (color changes) and no ink splash.
 */
fun Modifier.noRipple(enabled: Boolean = true, onClick: () -> Unit): Modifier =
    // No composed{} (that defeats modifier skipping); passing a null
    // interactionSource lets clickable create one lazily only if needed.
    this.clickable(
        interactionSource = null,
        indication = null,
        enabled = enabled,
        onClick = onClick,
    )

/** Pull-to-refresh wrapper used by every tab; yellow spinner per design. */
@androidx.compose.material3.ExperimentalMaterial3Api
@Composable
fun PullRefreshBox(
    refreshing: Boolean,
    onRefresh: () -> Unit,
    modifier: Modifier = Modifier,
    content: @Composable () -> Unit,
) {
    val state = androidx.compose.material3.pulltorefresh.rememberPullToRefreshState()
    androidx.compose.material3.pulltorefresh.PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = onRefresh,
        state = state,
        modifier = modifier,
        indicator = {
            androidx.compose.material3.pulltorefresh.PullToRefreshDefaults.Indicator(
                state = state,
                isRefreshing = refreshing,
                color = Tokens.Accent,
                containerColor = Tokens.Sheet,
                modifier = Modifier.align(Alignment.TopCenter),
            )
        },
    ) { content() }
}

/**
 * Ticks every [periodMs] while the calling composable is on screen — leaving
 * the tab cancels it, so only the visible screen polls. Fetches guard on
 * repository.node, so backgrounded (node released) ticks are free.
 */
@Composable
fun autoRefreshTick(periodMs: Long = 30_000): Int {
    var tick by androidx.compose.runtime.remember { androidx.compose.runtime.mutableIntStateOf(0) }
    androidx.compose.runtime.LaunchedEffect(kotlin.Unit) {
        while (true) {
            kotlinx.coroutines.delay(periodMs)
            tick++
        }
    }
    return tick
}

fun copyToClipboard(
    context: Context,
    label: String,
    value: String,
    sensitive: Boolean = false,
) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    val clip = ClipData.newPlainText(label, value)
    if (sensitive && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        // Keeps the value out of the Android 13+ paste preview toast.
        clip.description.extras = PersistableBundle().apply {
            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
        }
    }
    cm.setPrimaryClip(clip)
    if (!sensitive) {
        Toasts.show("$label copied")
        return
    }
    Toasts.show("$label copied — clears in 60s")
    // The clipboard is world-readable before Android 13 and synced off-device
    // by some keyboards; don't let a seed / private key linger there.
    Handler(Looper.getMainLooper()).postDelayed({
        val current = cm.primaryClip?.getItemAt(0)?.text?.toString()
        if (current == value) cm.clearPrimaryClip()
    }, 60_000)
}

/**
 * Marks the current Activity's window FLAG_SECURE while composed: blocks
 * screenshots, the Recents thumbnail, screen recording and MediaProjection.
 * Use it on any screen that reveals the seed.
 */
@Composable
fun SecureScreen() {
    val context = LocalContext.current
    DisposableEffect(Unit) {
        var c: Context? = context
        var activity: android.app.Activity? = null
        while (c is ContextWrapper) {
            if (c is android.app.Activity) { activity = c; break }
            c = c.baseContext
        }
        val window = activity?.window
        window?.addFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE)
        onDispose { window?.clearFlags(android.view.WindowManager.LayoutParams.FLAG_SECURE) }
    }
}

/** Filled yellow pill — the design's primary CTA. */
@Composable
fun PillButton(
    text: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    height: Int = 52,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .height(height.dp)
            .background(
                if (enabled) Tokens.Accent else Tokens.Accent.copy(alpha = .3f),
                RoundedCornerShape(999.dp),
            )
            .noRipple(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelLarge,
            color = Tokens.AccentInk,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 24.dp),
        )
    }
}

/** Translucent yellow pill (design: rgba(250,204,21,.1) + border). */
@Composable
fun SoftPillButton(
    text: String,
    modifier: Modifier = Modifier,
    height: Int = 44,
    color: Color = Tokens.Accent,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .height(height.dp)
            .background(color.copy(alpha = .10f), RoundedCornerShape(999.dp))
            .border(1.dp, color.copy(alpha = .25f), RoundedCornerShape(999.dp))
            .noRipple(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        if (icon != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(7.dp),
                modifier = Modifier.padding(horizontal = 6.dp)) {
                androidx.compose.material3.Icon(icon, null, tint = color, modifier = Modifier.size(13.dp))
                Text(
                    text,
                    style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.5.sp),
                    color = color, maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
            }
            return@Box
        }
        Text(
            text,
            style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.5.sp),
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(horizontal = 6.dp),
        )
    }
}

/** Border-only yellow pill (design's Copy/Generate secondary actions). */
@Composable
fun OutlinePillButton(
    text: String,
    modifier: Modifier = Modifier,
    height: Int = 48,
    onClick: () -> Unit,
) {
    Box(
        modifier = modifier
            .height(height.dp)
            .border(1.dp, Tokens.Accent.copy(alpha = .35f), RoundedCornerShape(999.dp))
            .noRipple(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium.copy(fontSize = 14.sp),
            color = Tokens.Accent,
            maxLines = 1,
            modifier = Modifier.padding(horizontal = 22.dp),
        )
    }
}

/** The design's 34x20 pill switch with a white knob. */
@Composable
fun DesignSwitch(checked: Boolean, onToggle: () -> Unit) {
    Box(
        modifier = Modifier
            .size(width = 34.dp, height = 20.dp)
            .background(
                if (checked) Tokens.Accent else Color(0x33FFFFFF),
                RoundedCornerShape(999.dp),
            )
            .noRipple(onClick = onToggle),
    ) {
        Box(
            modifier = Modifier
                .padding(2.dp)
                .size(16.dp)
                .align(if (checked) Alignment.CenterEnd else Alignment.CenterStart)
                .background(Color.White, CircleShape),
        )
    }
}

/** slow / normal / urgent selector cards (send + open channel sheets). */
@Composable
fun FeerateChips(selected: String, onSelect: (String) -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("slow" to "~1 day", "normal" to "~1 hour", "urgent" to "next block").forEach { (v, sub) ->
            val on = selected == v
            Column(
                modifier = Modifier
                    .weight(1f)
                    .background(if (on) Tokens.Accent.copy(alpha = .1f) else Tokens.CardDeep, RoundedCornerShape(12.dp))
                    .border(1.dp, if (on) Tokens.Accent.copy(alpha = .4f) else Color(0x17FFFFFF), RoundedCornerShape(12.dp))
                    .noRipple { onSelect(v) }
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(v, style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp), color = if (on) Tokens.Accent else Tokens.TextMid)
                Text(sub, style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp), color = Tokens.Faint, modifier = Modifier.padding(top = 2.dp))
            }
        }
    }
}

/** In-app toast pill per design (white, bottom-centered, auto-dismiss). */
object Toasts {
    val message = kotlinx.coroutines.flow.MutableStateFlow<Pair<Long, String>?>(null)
    fun show(text: String) {
        message.value = System.currentTimeMillis() to text
    }
}

/** Outlined danger pill. */
@Composable
fun DangerPillButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .height(48.dp)
            .border(1.dp, Tokens.Red.copy(alpha = .4f), RoundedCornerShape(999.dp))
            .noRipple(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium.copy(fontSize = 14.sp),
            color = Tokens.Red,
            modifier = Modifier.padding(horizontal = 24.dp),
        )
    }
}

/** Card container (#11171E, hairline border, r14). */
@Composable
fun DesignCard(
    modifier: Modifier = Modifier,
    background: Color = Tokens.Card,
    radius: Int = 14,
    borderColor: Color = Tokens.BorderSoft,
    onClick: (() -> Unit)? = null,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(background, RoundedCornerShape(radius.dp))
            .border(1.dp, borderColor, RoundedCornerShape(radius.dp))
            .then(if (onClick != null) Modifier.noRipple(onClick = onClick) else Modifier)
            .padding(14.dp),
        content = content,
    )
}

/** Status badge (tiny uppercase pill). */
@Composable
fun StatusBadge(text: String, color: Color) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelSmall.copy(letterSpacing = 0.4.sp),
        color = color,
        modifier = Modifier
            .background(color.copy(alpha = .12f), RoundedCornerShape(999.dp))
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

fun statusColor(status: String): Color = when (status.lowercase()) {
    "paid", "complete", "online", "active", "normal" -> Tokens.Green
    "expired", "failed", "offline" -> Tokens.Red
    "pending", "paying", "unpaid", "opening", "confirming" -> Tokens.Orange
    else -> Tokens.Dim
}

/** Round icon bubble used in list rows. */
@Composable
fun RowIcon(bg: Color, content: @Composable () -> Unit) {
    Box(
        modifier = Modifier.size(34.dp).background(bg, CircleShape),
        contentAlignment = Alignment.Center,
    ) { content() }
}

/** ours/theirs liquidity bar: yellow on purple track. */
@Composable
fun LiquidityBar(oursMsat: ULong, totalMsat: ULong, modifier: Modifier = Modifier, height: Int = 6) {
    val pct = if (totalMsat == 0uL) 0f else (oursMsat.toDouble() / totalMsat.toDouble()).toFloat()
    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(height.dp)
            .background(Tokens.Purple.copy(alpha = .35f), RoundedCornerShape(999.dp)),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(pct.coerceIn(0f, 1f))
                .height(height.dp)
                .background(Tokens.Accent, RoundedCornerShape(999.dp)),
        )
    }
}

/**
 * Key-value panel used by every detail sheet. Tapping a row whose value is
 * always monospace (design); the third flag marks copyable rows (icon + tap-to-copy).
 */
@Composable
fun KvPanel(rows: List<Triple<String, String, Boolean>>, valueColor: (String) -> Color = { Tokens.TextMid }) {
    val context = androidx.compose.ui.platform.LocalContext.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.CardDeep, RoundedCornerShape(16.dp))
            .border(1.dp, Tokens.Border.copy(alpha = .5f), RoundedCornerShape(16.dp)),
    ) {
        rows.forEachIndexed { i, (k, v, copyable) ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .then(
                        if (copyable) Modifier.noRipple { copyToClipboard(context, k, v) }
                        else Modifier
                    )
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Text(
                    k,
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontWeight = FontWeight.Bold),
                    color = Tokens.Faint,
                    modifier = Modifier.padding(top = 1.dp).width(104.dp),
                )
                Text(
                    v,
                    style = MaterialTheme.typography.bodySmall.copy(
                        fontSize = 13.sp,
                        fontWeight = FontWeight.SemiBold,
                        fontFamily = MonoFont,
                    ),
                    color = valueColor(k),
                    modifier = Modifier.weight(1f),
                )
                if (copyable) {
                    androidx.compose.material3.Icon(
                        androidx.compose.material.icons.Icons.Outlined.ContentCopy,
                        contentDescription = "copy",
                        tint = Tokens.Faint,
                        modifier = Modifier.size(11.dp).align(Alignment.CenterVertically),
                    )
                }
            }
            if (i != rows.lastIndex) {
                Box(Modifier.fillMaxWidth().height(1.dp).background(Color(0x0AFFFFFF)))
            }
        }
    }
}

/** Big numeral in Space Grotesk with a small dim unit suffix. */
@Composable
fun BalanceText(amount: String, unit: String, color: Color = Tokens.Text, size: Int = 32) {
    Row(verticalAlignment = Alignment.Bottom) {
        Text(
            amount,
            style = MaterialTheme.typography.displaySmall.copy(fontSize = size.sp),
            color = color,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            " $unit",
            style = MaterialTheme.typography.bodyLarge.copy(fontFamily = SpaceGrotesk, fontSize = (size * 15 / 32).sp),
            color = Tokens.Dim,
            modifier = Modifier.padding(bottom = 4.dp),
        )
    }
}

/**
 * Numbered 2-column BIP39 word grid. Until [revealed], words are masked
 * (Compose blur() is a no-op below Android 12, so masking is the safe way)
 * and a tap anywhere reveals them.
 */
@Composable
fun SeedGrid(words: List<String>, revealed: Boolean, onReveal: () -> Unit) {
    Box(modifier = Modifier.noRipple(enabled = !revealed, onClick = onReveal)) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        words.chunked(2).forEachIndexed { row, pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEachIndexed { col, word ->
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .background(Tokens.Field, RoundedCornerShape(12.dp))
                            .border(1.dp, Color(0x0FFFFFFF), RoundedCornerShape(12.dp))
                            .padding(horizontal = 14.dp, vertical = 11.dp),
                        horizontalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Text(
                            "${row * 2 + col + 1}",
                            style = MaterialTheme.typography.bodySmall.copy(
                                fontSize = 12.5.sp,
                                fontFamily = app.light.wallet.ui.theme.MonoFont,
                                fontWeight = FontWeight.SemiBold,
                            ),
                            color = Tokens.Faint,
                        )
                        Text(
                            if (revealed) word else "••••••",
                            style = MaterialTheme.typography.bodyMedium.copy(
                                fontSize = 14.sp,
                                fontFamily = app.light.wallet.ui.theme.MonoFont,
                                fontWeight = FontWeight.SemiBold,
                            ),
                            color = if (revealed) Tokens.Text else Tokens.Faint,
                            maxLines = 1,
                            // Keep the words out of the accessibility tree so a
                            // rogue a11y service can't read the seed.
                            modifier = Modifier.clearAndSetSemantics {},
                        )
                    }
                }
            }
        }
    }
    if (!revealed) {
        Box(
            modifier = Modifier
                .matchParentSize(),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                "Tap to reveal",
                style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.sp),
                color = Tokens.Accent,
                modifier = Modifier
                    .background(Color(0xD90A0E12), RoundedCornerShape(999.dp))
                    .border(1.dp, Tokens.Accent.copy(alpha = .4f), RoundedCornerShape(999.dp))
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            )
        }
    }
    }
}

fun qrBitmap(data: String, sizePx: Int = 512): ImageBitmap? = runCatching {
    val matrix = QRCodeWriter().encode(
        data, BarcodeFormat.QR_CODE, sizePx, sizePx,
        mapOf(EncodeHintType.MARGIN to 1),
    )
    val pixels = IntArray(sizePx * sizePx)
    for (y in 0 until sizePx) for (x in 0 until sizePx) {
        pixels[y * sizePx + x] = if (matrix.get(x, y)) 0xFF000000.toInt() else 0xFFFFFFFF.toInt()
    }
    android.graphics.Bitmap.createBitmap(pixels, sizePx, sizePx, android.graphics.Bitmap.Config.ARGB_8888)
        .asImageBitmap()
}.getOrNull()
