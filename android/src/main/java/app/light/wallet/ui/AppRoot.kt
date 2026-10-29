package app.light.wallet.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Circle
import androidx.compose.material.icons.outlined.Home
import androidx.compose.material.icons.outlined.Hub
import androidx.compose.material.icons.outlined.ReceiptLong
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.ViewInAr
import androidx.compose.material.icons.outlined.SwapHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.data.ActivePaymentStatus
import app.light.wallet.data.ConnState
import app.light.wallet.data.WalletRepository
import app.light.wallet.ui.channels.ChannelsTab
import app.light.wallet.ui.home.MainTab
import app.light.wallet.ui.invoices.InvoicesTab
import app.light.wallet.ui.onboarding.OnboardingFlow
import app.light.wallet.ui.settings.SettingsTab
import app.light.wallet.ui.sheets.SheetHost
import app.light.wallet.ui.sheets.WalletSheet
import app.light.wallet.ui.theme.Tokens
import app.light.wallet.ui.transactions.TransactionsTab

enum class Tab(val label: String, val icon: ImageVector) {
    MAIN("Main", Icons.Outlined.Home),
    INVOICES("Invoices", Icons.Outlined.ReceiptLong),
    TRANSACTIONS("Transactions", Icons.Outlined.SwapHoriz),
    CHANNELS("Channels", Icons.Outlined.Hub),
    UTXOS("UTXOs", Icons.Outlined.ViewInAr),
    SETTINGS("Settings", Icons.Outlined.Settings),
}

@Composable
fun AppRoot(repository: WalletRepository) {
    var onboarded by remember { mutableStateOf(repository.hasWallet()) }

    if (!onboarded) {
        OnboardingFlow(repository = repository, onDone = {
            onboarded = true
            repository.connectInBackground()
        })
        return
    }

    var tab by remember { mutableStateOf(Tab.MAIN) }
    var sheet by remember { mutableStateOf<WalletSheet?>(null) }
    // (counter, segment): asks the Invoices tab to select a segment.
    var invoicesSegmentRequest by remember { mutableStateOf(0 to 0) }
    // (counter, txid): asks the Transactions tab to expand one card.
    var txExpandRequest by remember { mutableStateOf<Pair<Int, String?>>(0 to null) }

    // Two-level back model: an open sheet consumes back first (handled by
    // ModalBottomSheet itself, returning to the screen that opened it);
    // otherwise back from any tab lands on Main; back on Main exits.
    BackHandler(enabled = sheet == null && tab != Tab.MAIN) {
        tab = Tab.MAIN
    }
    val active by repository.activePayments.collectAsState()
    val hasPending = active.any { it.status == ActivePaymentStatus.PAYING || it.status == ActivePaymentStatus.PENDING }

    Box(modifier = Modifier.fillMaxSize().background(Tokens.Bg)) {
        Column(modifier = Modifier.fillMaxSize()) {
            Box(modifier = Modifier.weight(1f).statusBarsPadding()) {
                AnimatedContent(
                    targetState = tab,
                    transitionSpec = {
                        // Fast, light: a short directional slide + crossfade with
                        // the container size snapped (no slow spring relayout that
                        // makes the screen feel like it takes a moment to open).
                        val dir = if (targetState.ordinal > initialState.ordinal) 1 else -1
                        (fadeIn(tween(110)) +
                            slideInHorizontally(tween(150)) { (dir * it) / 14 }) togetherWith
                            fadeOut(tween(90)) using
                            androidx.compose.animation.SizeTransform(clip = false) { _, _ ->
                                androidx.compose.animation.core.snap()
                            }
                    },
                    label = "tab",
                ) { t ->
                    when (t) {
                        Tab.MAIN -> MainTab(
                            repository,
                            onOpenSheet = { sheet = it },
                            onGoTransactions = { tab = Tab.TRANSACTIONS },
                            onRecentInvoice = { inv ->
                                tab = Tab.INVOICES
                                invoicesSegmentRequest = invoicesSegmentRequest.first + 1 to 0
                                sheet = WalletSheet.InvoiceDetail(inv)
                            },
                            onRecentPay = { p ->
                                tab = Tab.INVOICES
                                invoicesSegmentRequest = invoicesSegmentRequest.first + 1 to 1
                                sheet = WalletSheet.PaymentDetail(p)
                            },
                            onRecentTx = { txid ->
                                tab = Tab.TRANSACTIONS
                                txExpandRequest = txExpandRequest.first + 1 to txid
                            },
                        )
                        Tab.INVOICES -> InvoicesTab(repository,
                            onOpenSheet = { sheet = it },
                            segmentRequest = invoicesSegmentRequest)
                        Tab.TRANSACTIONS -> TransactionsTab(repository, expandRequest = txExpandRequest)
                        Tab.CHANNELS -> ChannelsTab(repository, onOpenSheet = { sheet = it })
                        Tab.UTXOS -> app.light.wallet.ui.utxo.UtxoTab(repository)
                        Tab.SETTINGS -> SettingsTab(repository,
                            onOpenSheet = { sheet = it },
                            onWalletWiped = { onboarded = false })
                    }
                }
            }
            TabBar(tab, hasPending) { tab = it }
        }
        // Design toast pill (white, bottom-centered, auto-dismiss).
        val toastMsg by app.light.wallet.ui.Toasts.message.collectAsState()
        toastMsg?.let { (stamp, text) ->
            androidx.compose.runtime.LaunchedEffect(stamp) {
                kotlinx.coroutines.delay(1800)
                if (app.light.wallet.ui.Toasts.message.value?.first == stamp) {
                    app.light.wallet.ui.Toasts.message.value = null
                }
            }
            Box(
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 110.dp)
                    .background(Tokens.Text, RoundedCornerShape(999.dp))
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            ) {
                Text(
                    text,
                    style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp),
                    color = Tokens.Bg,
                )
            }
        }

        // Boot pill: floating status while the node is being scheduled.
        val connState by repository.connState.collectAsState()
        if (connState is ConnState.Connecting) {
            Row(
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .statusBarsPadding()
                    .padding(top = 52.dp)
                    .background(Color(0xF210181E), RoundedCornerShape(999.dp))
                    .border(1.dp, Tokens.Accent.copy(alpha = .3f), RoundedCornerShape(999.dp))
                    .padding(horizontal = 16.dp, vertical = 9.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                androidx.compose.material3.CircularProgressIndicator(
                    color = Tokens.Accent, strokeWidth = 2.dp,
                    modifier = Modifier.size(13.dp),
                )
                Text(
                    "Contacting Greenlight scheduler…",
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.Bold),
                    color = Tokens.TextMid,
                )
            }
        }
        SheetHost(
            repository, sheet,
            onClose = { sheet = null },
            onOpenSheet = { sheet = it },
            onWalletWiped = { onboarded = false },
            onPaymentStarted = { id ->
                // Design flow: land on Invoices -> Payments with the live
                // payment detail sheet on top.
                tab = Tab.INVOICES
                invoicesSegmentRequest = invoicesSegmentRequest.first + 1 to 1
                sheet = WalletSheet.ActivePaymentDetail(id)
            },
        )
    }
}

@Composable
private fun TabBar(current: Tab, hasPending: Boolean, onPick: (Tab) -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.Sheet.copy(alpha = .95f))
            .padding(top = 8.dp)
            .navigationBarsPadding(),
    ) {
        Tab.entries.forEach { t ->
            val color = if (t == current) Tokens.Accent else Tokens.Faint
            Column(
                modifier = Modifier
                    .weight(1f)
                    .noRipple { onPick(t) }
                    .padding(top = 6.dp, bottom = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Box {
                    Icon(t.icon, contentDescription = t.label, tint = color, modifier = Modifier.size(21.dp))
                    if (t == Tab.INVOICES && hasPending) {
                        Icon(
                            Icons.Filled.Circle, contentDescription = "pending",
                            tint = Tokens.Orange,
                            modifier = Modifier.size(8.dp).align(Alignment.TopEnd),
                        )
                    }
                }
                Text(
                    t.label,
                    // Design is 10px; the longest label ("Transactions") needs
                    // one step down to survive 360dp-wide screens with 6 tabs.
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontSize = if (t.label.length > 10) 9.sp else 10.sp,
                    ),
                    color = color,
                    maxLines = 1,
                    softWrap = false,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
    }
}
