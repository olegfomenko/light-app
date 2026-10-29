@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package app.light.wallet.ui.utxo

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ViewInAr
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.core.OnchainOutput
import app.light.wallet.data.WalletRepository
import app.light.wallet.ui.DisplayUnit
import app.light.wallet.ui.PullRefreshBox
import app.light.wallet.ui.formatAmount
import app.light.wallet.ui.noRipple
import app.light.wallet.ui.theme.MonoFont
import app.light.wallet.ui.theme.SpaceGrotesk
import app.light.wallet.ui.theme.Tokens
import app.light.wallet.ui.transactions.openMempool
import app.light.wallet.ui.transactions.utxoStatusColor
import kotlinx.coroutines.launch

private val FILTERS = listOf("unconfirmed", "confirmed", "spent", "immature")

@Composable
fun UtxoTab(repository: WalletRepository) {
    val context = LocalContext.current
    val uiScope = rememberCoroutineScope()
    val funds by repository.funds.collectAsState()
    val connState by repository.connState.collectAsState()
    var filter by remember { mutableStateOf("confirmed") }
    var refreshing by remember { mutableStateOf(false) }
    val unit = DisplayUnit.from(repository.displayUnit)

    LaunchedEffect(connState) {
        if (repository.node != null && repository.funds.value == null) repository.refreshFunds()
    }

    // Newest first: unconfirmed (no height) on top, then descending height.
    val utxos = remember(funds, filter) {
        funds?.outputs.orEmpty()
            .filter { it.status == filter }
            .sortedByDescending { it.blockheight ?: UInt.MAX_VALUE }
    }

    PullRefreshBox(
        refreshing = refreshing,
        onRefresh = {
            refreshing = true
            uiScope.launch { repository.refreshFunds().join(); refreshing = false }
        },
    ) {
        Column(modifier = Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
            Text("UTXOs", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(top = 6.dp, bottom = 4.dp))
            Text(
                "On-chain outputs",
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp),
                color = Tokens.Faint,
                modifier = Modifier.padding(bottom = 14.dp),
            )
            androidx.compose.foundation.layout.FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                FILTERS.forEach { f ->
                    val on = filter == f
                    Box(
                        modifier = Modifier
                            .background(if (on) Tokens.Accent.copy(alpha = .1f) else Tokens.Card, RoundedCornerShape(999.dp))
                            .border(1.dp, if (on) Tokens.Accent.copy(alpha = .4f) else Tokens.BorderSoft, RoundedCornerShape(999.dp))
                            .noRipple { filter = f }
                            .padding(horizontal = 13.dp, vertical = 8.dp),
                    ) {
                        Text(
                            f.replaceFirstChar { it.uppercase() },
                            style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp),
                            color = if (on) Tokens.Accent else Tokens.Dim,
                        )
                    }
                }
            }
            LazyColumn(
                modifier = Modifier.padding(top = 14.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(utxos, key = { "${it.txid}:${it.output}" }) { u ->
                    UtxoRow(u, unit) {
                        // Address page shows the UTXO's full life; fall back to
                        // the funding tx when the node reports no address.
                        val path = u.address?.let { a -> "address/$a" } ?: "tx/${u.txid}"
                        openMempool(context, path)
                    }
                }
                if (utxos.isEmpty()) {
                    item {
                        Text(
                            if (funds == null) "Loading…" else "No $filter outputs",
                            style = MaterialTheme.typography.bodySmall,
                            color = Tokens.Faint,
                            modifier = Modifier.fillMaxWidth().padding(top = 36.dp),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun UtxoRow(u: OnchainOutput, unit: DisplayUnit, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.Card, RoundedCornerShape(14.dp))
            .border(1.dp, Tokens.BorderSoft, RoundedCornerShape(14.dp))
            .noRipple(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier.size(34.dp).background(Tokens.Accent.copy(alpha = .07f), CircleShape),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Outlined.ViewInAr, null, tint = Tokens.Accent, modifier = Modifier.size(15.dp)) }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                "${u.txid.take(6)}…${u.txid.takeLast(5)}:${u.output}",
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp, fontFamily = MonoFont, fontWeight = FontWeight.SemiBold),
            )
            Text(
                u.address ?: "—",
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontFamily = MonoFont),
                color = Tokens.Dim, maxLines = 1,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                formatAmount(u.amountMsat, unit),
                style = MaterialTheme.typography.bodyMedium.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.SemiBold, fontSize = 15.sp),
            )
            Text(
                u.status.replaceFirstChar { it.uppercase() },
                style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.5.sp),
                color = utxoStatusColor(u.status),
            )
        }
    }
}
