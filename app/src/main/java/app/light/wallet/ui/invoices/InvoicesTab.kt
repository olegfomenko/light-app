package app.light.wallet.ui.invoices

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.HourglassTop
import androidx.compose.material3.Icon
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.core.InvoiceEntry
import app.light.wallet.core.PayListEntry
import app.light.wallet.data.ActivePaymentStatus
import app.light.wallet.data.WalletRepository
import app.light.wallet.ui.noRipple
import app.light.wallet.ui.PillButton
import app.light.wallet.ui.RowIcon
import app.light.wallet.ui.StatusBadge
import app.light.wallet.ui.DisplayUnit
import app.light.wallet.ui.formatAmount
import app.light.wallet.ui.formatUnixTime
import app.light.wallet.ui.expiresIn
import app.light.wallet.ui.relativeTime
import app.light.wallet.ui.sheets.WalletSheet
import app.light.wallet.ui.shortId
import app.light.wallet.ui.statusColor
import app.light.wallet.ui.theme.MonoFont
import app.light.wallet.ui.theme.SpaceGrotesk
import app.light.wallet.ui.theme.Tokens
import kotlinx.coroutines.launch

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun InvoicesTab(
    repository: WalletRepository,
    onOpenSheet: (WalletSheet) -> Unit,
    segmentRequest: Pair<Int, Int> = 0 to 0,
) {
    var segment by remember { mutableStateOf(0) } // 0 created, 1 payments
    // Navigation elsewhere (recent activity, payment started) picks a segment.
    LaunchedEffect(segmentRequest) {
        if (segmentRequest.first > 0) segment = segmentRequest.second
    }
    val uiScope = androidx.compose.runtime.rememberCoroutineScope()
    val invoicesRaw by repository.invoices.collectAsState()
    val paysRaw by repository.pays.collectAsState()
    val active by repository.activePayments.collectAsState()
    val connState by repository.connState.collectAsState()
    var refreshing by remember { mutableStateOf(false) }
    val unit = DisplayUnit.from(repository.displayUnit)
    val pendingCount = active.count { it.status == ActivePaymentStatus.PAYING || it.status == ActivePaymentStatus.PENDING }
    val invoices = remember(invoicesRaw) { invoicesRaw.orEmpty().sortedByDescending { it.createdIndex } }
    val pays = remember(paysRaw) { paysRaw.orEmpty().sortedByDescending { it.createdAt } }

    // First entry only; afterwards pull-to-refresh or actions update the flows.
    LaunchedEffect(connState) {
        if (repository.node != null && repository.invoices.value == null) {
            repository.refreshInvoices(); repository.refreshPays()
        }
    }

    app.light.wallet.ui.PullRefreshBox(
        refreshing = refreshing,
        onRefresh = {
            refreshing = true
            uiScope.launch {
                repository.refreshInvoices().join()
                repository.refreshPays().join()
                refreshing = false
            }
        },
    ) {
    Column(modifier = Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
        Text(
            "Invoices",
            style = MaterialTheme.typography.headlineSmall,
            modifier = Modifier.padding(top = 6.dp, bottom = 14.dp),
        )
        // segmented control
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Tokens.Card, RoundedCornerShape(999.dp))
                .border(1.dp, Tokens.Border, RoundedCornerShape(999.dp))
                .padding(4.dp),
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Segment("Created", segment == 0, Modifier.weight(1f)) { segment = 0 }
            Segment(
                if (pendingCount > 0) "Payments · $pendingCount" else "Payments",
                segment == 1, Modifier.weight(1f),
            ) { segment = 1 }
        }

        LazyColumn(
            modifier = Modifier.weight(1f).padding(top = 14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (segment == 0) {
                items(invoices) { inv ->
                    InvoiceRow(inv, unit) { onOpenSheet(WalletSheet.InvoiceDetail(inv)) }
                }
                if (invoices.isEmpty()) item { Empty("No invoices created yet.") }
            } else {
                val liveInvstrings = active
                    .filter { it.status == ActivePaymentStatus.PAYING || it.status == ActivePaymentStatus.PENDING }
                    .map { it.invstring }.toSet()
                items(active.filter { it.status == ActivePaymentStatus.PAYING || it.status == ActivePaymentStatus.PENDING }) { p ->
                    ActivePayRow(unit, p.status, p.description ?: shortId(p.invstring, 12), mono = p.description == null) { onOpenSheet(WalletSheet.ActivePaymentDetail(p.id)) }
                }
                // Don't also render the listpays row for a payment we're still
                // showing as a live in-flight card.
                items(pays.filter { it.bolt11 !in liveInvstrings && it.bolt12 !in liveInvstrings }) { p ->
                    PayRow(p, unit) { onOpenSheet(WalletSheet.PaymentDetail(p)) }
                }
                if (pays.isEmpty() && pendingCount == 0) item { Empty("No payments yet.") }
            }
        }

        PillButton(
            if (segment == 0) "Create invoice" else "Pay invoice",
            modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp),
            height = 50,
        ) {
            onOpenSheet(if (segment == 0) WalletSheet.NewInvoice else WalletSheet.Pay())
        }
    }
    }
}

@Composable
private fun Segment(text: String, on: Boolean, modifier: Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .height(36.dp)
            .background(if (on) Tokens.Field else androidx.compose.ui.graphics.Color.Transparent, RoundedCornerShape(999.dp))
            .noRipple(onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.sp),
            color = if (on) Tokens.Text else Tokens.Dim,
        )
    }
}

@Composable
private fun Empty(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall, color = Tokens.Faint,
        modifier = Modifier.padding(top = 24.dp))
}

@Composable
private fun InvoiceRow(inv: InvoiceEntry, unit: DisplayUnit, onClick: () -> Unit) {
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
            modifier = Modifier.size(34.dp).background(Tokens.Accent.copy(alpha = .07f), androidx.compose.foundation.shape.CircleShape),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.Bolt, null, tint = Tokens.Accent, modifier = Modifier.size(14.dp)) }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                inv.description?.ifBlank { null } ?: inv.label,
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
            Text(
                if (inv.status == "paid") relativeTime(inv.paidAt) else formatUnixTime(inv.expiresAt),
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp),
                color = Tokens.Dim,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                formatAmount(inv.amountMsat, unit),
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp, fontFamily = SpaceGrotesk, fontWeight = FontWeight.SemiBold),
            )
            StatusBadge(inv.status, statusColor(inv.status))
        }
    }
}

@Composable
private fun PayRow(p: PayListEntry, unit: DisplayUnit, onClick: () -> Unit) {
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
        val c = statusColor(p.status)
        RowIcon(c.copy(alpha = .1f)) {
            Icon(Icons.Filled.ArrowUpward, null, tint = c, modifier = Modifier.size(15.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                p.description?.ifBlank { null } ?: shortId(p.destination, 8),
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
            Text(
                relativeTime(p.completedAt ?: p.createdAt),
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp),
                color = Tokens.Dim,
            )
        }
        Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(
                "−" + formatAmount(p.amountMsat, unit),
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 14.5.sp, fontFamily = SpaceGrotesk, fontWeight = FontWeight.SemiBold),
            )
            StatusBadge(p.status, statusColor(p.status))
        }
    }
}

@Composable
private fun ActivePayRow(
    unit: DisplayUnit,
    status: ActivePaymentStatus,
    subtitle: String,
    mono: Boolean,
    onClick: () -> Unit,
) {
    val pending = status == ActivePaymentStatus.PENDING
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.Card, RoundedCornerShape(14.dp))
            .border(1.dp, Tokens.Orange.copy(alpha = .3f), RoundedCornerShape(14.dp))
            .noRipple(onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 13.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RowIcon(Tokens.Orange.copy(alpha = .1f)) {
            Icon(Icons.Filled.HourglassTop, null, tint = Tokens.Orange, modifier = Modifier.size(15.dp))
        }
        Column(modifier = Modifier.weight(1f)) {
            Text(
                if (pending) "Payment pending" else "Routing payment…",
                style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold),
            )
            Text(subtitle, style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontFamily = if (mono) MonoFont else null), color = Tokens.Faint)
        }
        StatusBadge(if (pending) "pending" else "paying", Tokens.Orange)
    }
}
