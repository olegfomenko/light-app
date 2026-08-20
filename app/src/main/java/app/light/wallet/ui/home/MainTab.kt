@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package app.light.wallet.ui.home

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.CurrencyBitcoin
import androidx.compose.material.icons.filled.MoreHoriz
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.data.ConnState
import app.light.wallet.data.WalletRepository
import app.light.wallet.ui.DisplayUnit
import app.light.wallet.ui.LiquidityBar
import app.light.wallet.ui.PullRefreshBox
import app.light.wallet.ui.RowIcon
import app.light.wallet.ui.SoftPillButton
import app.light.wallet.ui.autoRefreshTick
import app.light.wallet.ui.copyToClipboard
import app.light.wallet.ui.formatAmount
import app.light.wallet.ui.formatCompactSat
import app.light.wallet.ui.noRipple
import app.light.wallet.ui.relativeTime
import app.light.wallet.ui.satsToBtcLine
import app.light.wallet.ui.sheets.WalletSheet
import app.light.wallet.ui.shortId
import app.light.wallet.ui.theme.MonoFont
import app.light.wallet.ui.theme.SpaceGrotesk
import app.light.wallet.ui.theme.Tokens
import kotlinx.coroutines.launch

private data class RecentItem(
    val label: String, val time: String, val amount: String,
    val amountColor: Color, val iconColor: Color, val chain: Boolean, val sort: ULong,
    val onClick: () -> Unit,
)

@Composable
fun MainTab(
    repository: WalletRepository,
    onOpenSheet: (WalletSheet) -> Unit,
    onGoTransactions: () -> Unit,
    onRecentInvoice: (app.light.wallet.core.InvoiceEntry) -> Unit = {},
    onRecentPay: (app.light.wallet.core.PayListEntry) -> Unit = {},
    onRecentTx: (String) -> Unit = {},
) {
    val context = LocalContext.current
    val uiScope = rememberCoroutineScope()
    val connState by repository.connState.collectAsState()
    val funds by repository.funds.collectAsState()
    val invoices by repository.invoices.collectAsState()
    val pays by repository.pays.collectAsState()
    val transactions by repository.transactions.collectAsState()
    var refreshing by remember { mutableStateOf(false) }
    val tick = autoRefreshTick()
    val unit = DisplayUnit.from(repository.displayUnit)

    // The Main screen is the only one that auto-refreshes (every 30s while
    // visible); everything else waits for pull-to-refresh or an action.
    LaunchedEffect(tick, connState) {
        if (repository.node != null) repository.refreshMain()
    }

    // Recent activity: paid invoices + lightning payments + on-chain
    // transactions, all derived from the shared flows.
    val recent = remember(funds, invoices, pays, transactions, connState, unit) {
        val now = (System.currentTimeMillis() / 1000).toULong()
        val tip = (connState as? ConnState.Connected)?.info?.blockheight ?: 0u
        val inv = invoices.orEmpty().filter { it.status == "paid" }.map { i ->
            RecentItem(
                label = i.description?.ifBlank { null } ?: i.label,
                time = relativeTime(i.paidAt),
                amount = "+" + formatAmount(i.amountReceivedMsat, unit),
                amountColor = Tokens.Green, iconColor = Tokens.Green,
                chain = false, sort = i.paidAt ?: 0uL,
                onClick = { onRecentInvoice(i) },
            )
        }
        val sent = pays.orEmpty().map { p ->
            RecentItem(
                label = p.description?.ifBlank { null } ?: shortId(p.destination, 8),
                time = relativeTime(p.completedAt ?: p.createdAt),
                amount = "−" + formatAmount(p.amountMsat, unit),
                amountColor = Tokens.Text, iconColor = Tokens.Red,
                chain = false, sort = p.completedAt ?: p.createdAt ?: 0uL,
                onClick = { onRecentPay(p) },
            )
        }
        // On-chain: whole transactions, valued as the net of the inputs and
        // outputs our node tracks (deposits positive, withdrawals negative).
        val tracked = funds?.outputs.orEmpty().associateBy { it.txid to it.output }
        val chain = transactions.orEmpty().mapNotNull { tx ->
            val inSum = tx.inputs.sumOf { i -> (tracked[i.txid to i.index]?.amountMsat ?: 0uL).toLong() }
            val outSum = tx.outputs.sumOf { o -> (tracked[tx.txid to o.index]?.amountMsat ?: 0uL).toLong() }
            val net = outSum - inSum
            if (inSum == 0L && outSum == 0L) return@mapNotNull null
            val confirmed = tx.blockheight > 0u
            val ts = if (!confirmed || tip == 0u || tip < tx.blockheight) now
            else now - ((tip - tx.blockheight).toULong() * 600uL)
            RecentItem(
                label = if (net >= 0) "Received bitcoin" else "Sent bitcoin",
                time = if (!confirmed) "confirming…" else relativeTime(ts),
                amount = (if (net >= 0) "+" else "−") + formatAmount(kotlin.math.abs(net).toULong(), unit),
                amountColor = if (net >= 0) Tokens.Green else Tokens.Text,
                iconColor = Tokens.Btc,
                chain = true, sort = ts,
                onClick = { onRecentTx(tx.txid) },
            )
        }
        (inv + sent + chain).sortedByDescending { it.sort }.take(4)
    }

    val f = funds
    PullRefreshBox(
        refreshing = refreshing,
        onRefresh = {
            refreshing = true
            uiScope.launch {
                repository.refreshFunds().join()
                repository.refreshInvoices().join()
                repository.refreshPays().join()
                refreshing = false
            }
        },
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp),
        ) {
            // ── Header ──
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                androidx.compose.foundation.Image(
                    painter = androidx.compose.ui.res.painterResource(app.light.wallet.R.drawable.logo_lightapp_small),
                    contentDescription = null,
                    modifier = Modifier
                        .size(34.dp)
                        .clip(RoundedCornerShape(9.dp)),
                )
                Text(
                    "LightApp",
                    style = MaterialTheme.typography.titleMedium.copy(fontSize = 17.sp),
                    modifier = Modifier.weight(1f),
                )
                val (chipText, chipColor) = when (connState) {
                    is ConnState.Connected -> "Node running" to Tokens.Green
                    is ConnState.Connecting -> "Connecting…" to Tokens.Orange
                    is ConnState.Failed -> "Offline" to Tokens.Red
                    else -> "Idle" to Tokens.Dim
                }
                Row(
                    modifier = Modifier
                        .background(chipColor.copy(alpha = .08f), RoundedCornerShape(999.dp))
                        .border(1.dp, chipColor.copy(alpha = .25f), RoundedCornerShape(999.dp))
                        .noRipple { if (connState is ConnState.Failed) repository.connectInBackground(force = true) }
                        .padding(horizontal = 11.dp, vertical = 5.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Box(Modifier.size(6.dp).background(chipColor, CircleShape))
                    Text(chipText, style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontWeight = FontWeight.Bold), color = chipColor)
                }
            }

            // ── Bitcoin on-chain card ──
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(
                        Brush.linearGradient(listOf(Color(0xFF141B23), Color(0xFF10161C))),
                        RoundedCornerShape(20.dp),
                    )
                    .border(1.dp, Tokens.Border, RoundedCornerShape(20.dp))
                    .padding(20.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(Modifier.size(22.dp).background(Tokens.Btc, CircleShape), contentAlignment = Alignment.Center) {
                        Text(
                            "₿",
                            style = MaterialTheme.typography.labelSmall.copy(
                                fontSize = 12.sp,
                                fontFamily = app.light.wallet.ui.theme.SpaceGrotesk,
                            ),
                            color = Color.White,
                        )
                    }
                    Text("Bitcoin · on-chain", style = MaterialTheme.typography.labelMedium, color = Tokens.Label)
                }
                // Design: one total figure (confirmed + unconfirmed), no
                // BTC-conversion/pending subtitle line.
                val chain = f?.let { it.onchainConfirmedMsat + it.onchainUnconfirmedMsat }
                Box(Modifier.padding(top = 14.dp)) {
                    app.light.wallet.ui.BalanceText(
                        amount = formatAmount(chain, unit),
                        unit = unit.label,
                    )
                }
                Row(modifier = Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    SoftPillButton("Receive", modifier = Modifier.weight(1f),
                        icon = Icons.Filled.ArrowDownward) { onOpenSheet(WalletSheet.Receive) }
                    SoftPillButton("Send", modifier = Modifier.weight(1f),
                        icon = Icons.Filled.ArrowUpward) { onOpenSheet(WalletSheet.SendChain) }
                    MoreDot { onGoTransactions() }
                }
            }

            // ── Lightning card ──
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 14.dp)
                    .background(
                        Brush.linearGradient(listOf(Color(0xFF26200F), Color(0xFF181307))),
                        RoundedCornerShape(20.dp),
                    )
                    .border(1.dp, Tokens.Accent.copy(alpha = .2f), RoundedCornerShape(20.dp))
                    .padding(20.dp),
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box(
                        Modifier.size(22.dp).background(Tokens.Accent.copy(alpha = .15f), CircleShape),
                        contentAlignment = Alignment.Center,
                    ) { Icon(Icons.Filled.Bolt, null, tint = Tokens.Accent, modifier = Modifier.size(13.dp)) }
                    Text("Lightning", style = MaterialTheme.typography.labelMedium, color = Tokens.Label)
                    Spacer(Modifier.weight(1f))
                    val chCount = f?.channels?.size ?: 0
                    Text("$chCount channels", style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp), color = Tokens.Dim)
                }
                Box(Modifier.padding(top = 14.dp)) {
                    app.light.wallet.ui.BalanceText(
                        amount = formatAmount(f?.outboundMsat, unit),
                        unit = unit.label,
                        color = Tokens.Accent,
                    )
                }
                val nodeId = (connState as? ConnState.Connected)?.info?.id
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(top = 14.dp)
                        .height(1.dp)
                        .background(Tokens.Border),
                )
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(top = 12.dp)
                        .noRipple(enabled = nodeId != null) {
                            nodeId?.let { copyToClipboard(context, "Node ID", it) }
                        },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text(
                        "Node ID",
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontWeight = FontWeight.Bold),
                        color = Tokens.Dim,
                    )
                    Text(
                        shortId(nodeId, 12),
                        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp, fontFamily = MonoFont),
                        color = Tokens.TextMid,
                        maxLines = 1,
                        overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                        textAlign = androidx.compose.ui.text.style.TextAlign.End,
                        modifier = Modifier.weight(1f),
                    )
                    if (nodeId != null) Icon(Icons.Outlined.ContentCopy, null, tint = Tokens.Accent, modifier = Modifier.size(12.dp))
                }
                Row(modifier = Modifier.padding(top = 18.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .height(44.dp)
                            .background(Tokens.Accent, RoundedCornerShape(999.dp))
                            .noRipple { onOpenSheet(WalletSheet.NewInvoice) },
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            "Create invoice",
                            style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.5.sp),
                            color = Tokens.AccentInk,
                            maxLines = 1,
                            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                            modifier = Modifier.padding(horizontal = 6.dp),
                        )
                    }
                    SoftPillButton("Pay invoice", modifier = Modifier.weight(1f)) { onOpenSheet(WalletSheet.Pay()) }
                    MoreDot { onOpenSheet(WalletSheet.NodeInfoSheet) }
                }
            }

            // ── Recent activity ──
            Row(
                modifier = Modifier.fillMaxWidth().padding(top = 22.dp, bottom = 10.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                Text("Recent activity", style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            }
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(bottom = 16.dp)) {
                if (recent.isEmpty()) {
                    Text(
                        "No activity yet — create an invoice or get an on-chain address to receive funds.",
                        style = MaterialTheme.typography.bodySmall,
                        color = Tokens.Faint,
                    )
                }
                recent.forEach { item ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .background(Tokens.Card, RoundedCornerShape(14.dp))
                            .border(1.dp, Tokens.BorderSoft, RoundedCornerShape(14.dp))
                            .noRipple(onClick = item.onClick)
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        RowIcon(item.iconColor.copy(alpha = .1f)) {
                            Icon(
                                if (item.chain) Icons.Filled.CurrencyBitcoin else Icons.Filled.Bolt,
                                null, tint = item.iconColor, modifier = Modifier.size(15.dp),
                            )
                        }
                        Column(modifier = Modifier.weight(1f)) {
                            Text(item.label, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold), maxLines = 1)
                            Text(item.time, style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp), color = Tokens.Dim)
                        }
                        Text(
                            item.amount,
                            style = MaterialTheme.typography.bodyMedium.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.SemiBold),
                            color = item.amountColor,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun MoreDot(onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .size(44.dp)
            .background(Color(0x0FFFFFFF), CircleShape)
            .noRipple(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Filled.MoreHoriz, null, tint = Tokens.TextMid, modifier = Modifier.size(16.dp))
    }
}
