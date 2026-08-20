package app.light.wallet.ui.channels

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.core.PeerChannel
import app.light.wallet.data.WalletRepository
import app.light.wallet.ui.noRipple
import app.light.wallet.ui.LiquidityBar
import app.light.wallet.ui.StatusBadge
import app.light.wallet.ui.formatCompactSat
import app.light.wallet.ui.sheets.WalletSheet
import app.light.wallet.ui.shortId
import app.light.wallet.ui.statusColor
import app.light.wallet.ui.theme.MonoFont
import app.light.wallet.ui.theme.SpaceGrotesk
import app.light.wallet.ui.theme.Tokens
import kotlinx.coroutines.launch

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun ChannelsTab(repository: WalletRepository, onOpenSheet: (WalletSheet) -> Unit) {
    val uiScope = androidx.compose.runtime.rememberCoroutineScope()
    val channelsRaw by repository.channels.collectAsState()
    val connState by repository.connState.collectAsState()
    var refreshing by remember { mutableStateOf(false) }
    val channels = channelsRaw.orEmpty()

    LaunchedEffect(connState) {
        if (repository.node != null && repository.channels.value == null) repository.refreshChannels()
    }

    val usable = channels.filter { it.state == "CHANNELD_NORMAL" }
    val outbound = usable.sumOf { (it.toUsMsat ?: 0uL).toLong() }.toULong()
    val inbound = usable.sumOf { (it.toThemMsat ?: 0uL).toLong() }.toULong()
    val capacity = usable.sumOf { (it.totalMsat ?: 0uL).toLong() }.toULong()

    app.light.wallet.ui.PullRefreshBox(
        refreshing = refreshing,
        onRefresh = {
            refreshing = true
            uiScope.launch { repository.refreshChannels().join(); refreshing = false }
        },
    ) {
    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(top = 6.dp, bottom = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("Channels", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f))
            Box(
                modifier = Modifier
                    .height(38.dp)
                    .background(Tokens.Accent, RoundedCornerShape(999.dp))
                    .noRipple { onOpenSheet(WalletSheet.OpenChannel) }
                    .padding(horizontal = 16.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text("+ Open", style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.sp), color = Tokens.AccentInk)
            }
        }

        // Liquidity summary card
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Brush.linearGradient(listOf(Color(0xFF141B23), Color(0xFF10161C))), RoundedCornerShape(18.dp))
                .border(1.dp, Tokens.Border, RoundedCornerShape(18.dp))
                .padding(18.dp),
        ) {
            Row {
                Column(modifier = Modifier.weight(1f)) {
                    Text("Outbound", style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Dim)
                    Text(
                        formatCompactSat(outbound),
                        style = MaterialTheme.typography.displaySmall.copy(fontSize = 20.sp),
                        color = Tokens.Accent, modifier = Modifier.padding(top = 3.dp),
                    )
                }
                Box(Modifier.width(1.dp).height(44.dp).background(Tokens.Border))
                Column(modifier = Modifier.weight(1f).padding(start = 14.dp)) {
                    Text("Inbound", style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Dim)
                    Text(
                        formatCompactSat(inbound),
                        style = MaterialTheme.typography.displaySmall.copy(fontSize = 20.sp),
                        color = Tokens.Purple, modifier = Modifier.padding(top = 3.dp),
                    )
                }
            }
            LiquidityBar(outbound, outbound + inbound, modifier = Modifier.padding(top = 14.dp))
            Text(
                "Total capacity ${formatCompactSat(capacity)} across ${usable.size} channels",
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp),
                color = Tokens.Faint, modifier = Modifier.padding(top = 8.dp),
            )
        }

        LazyColumn(
            modifier = Modifier.weight(1f).padding(top = 14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(channels) { ch ->
                ChannelCard(ch) { onOpenSheet(WalletSheet.ChannelDetail(ch)) }
            }
            if (channels.isEmpty()) {
                item {
                    Text(
                        "No channels yet. Open one to a well-connected peer to start sending and receiving on Lightning.",
                        style = MaterialTheme.typography.bodySmall, color = Tokens.Faint,
                        modifier = Modifier.padding(top = 24.dp),
                    )
                }
            }
        }
    }
    }
}

@Composable
private fun ChannelCard(ch: PeerChannel, onClick: () -> Unit) {
    val stateLabel = when (ch.state) {
        "CHANNELD_NORMAL" -> if (ch.peerConnected) "active" else "offline"
        "CHANNELD_AWAITING_LOCKIN", "DUALOPEND_AWAITING_LOCKIN" -> "opening"
        "OPENINGD", "DUALOPEND_OPEN_INIT" -> "opening"
        else -> "closing"
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.Card, RoundedCornerShape(14.dp))
            .border(1.dp, Tokens.BorderSoft, RoundedCornerShape(14.dp))
            .noRipple(onClick = onClick)
            .padding(14.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Box(
                modifier = Modifier.size(32.dp).background(Tokens.Accent.copy(alpha = .1f), CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    ch.peerId.take(2).uppercase(),
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = SpaceGrotesk, fontWeight = FontWeight.Bold, fontSize = 12.sp),
                    color = Tokens.Accent,
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(shortId(ch.peerId, 8), style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, fontSize = 15.sp))
                Text(
                    ch.shortChannelId ?: shortId(ch.channelId, 8),
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontFamily = MonoFont),
                    color = Tokens.Dim,
                )
            }
            StatusBadge(stateLabel, statusColor(stateLabel))
        }
        LiquidityBar(ch.toUsMsat ?: 0uL, ch.totalMsat ?: 0uL, modifier = Modifier.padding(top = 12.dp), height = 5)
        Row(modifier = Modifier.fillMaxWidth().padding(top = 6.dp)) {
            Text("Ours ", style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp), color = Tokens.Dim)
            Text(formatCompactSat(ch.toUsMsat), style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Accent)
            Spacer(Modifier.weight(1f))
            Text("Theirs ", style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp), color = Tokens.Dim)
            Text(formatCompactSat(ch.toThemMsat), style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Purple)
        }
    }
}
