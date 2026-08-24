package app.light.wallet.ui.sheets

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.ModalBottomSheetProperties
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.core.CloseChannelParams
import app.light.wallet.core.CreateInvoiceParams
import app.light.wallet.core.DecodedInvoice
import app.light.wallet.core.OpenChannelParams
import app.light.wallet.core.WithdrawParams
import app.light.wallet.core.XpayParams
import app.light.wallet.data.ActivePaymentStatus
import app.light.wallet.data.ConnState
import app.light.wallet.data.PayCommand
import app.light.wallet.data.WalletRepository
import app.light.wallet.ui.noRipple
import app.light.wallet.ui.DangerPillButton
import app.light.wallet.ui.KvPanel
import app.light.wallet.ui.PillButton
import app.light.wallet.ui.SoftPillButton
import app.light.wallet.ui.DisplayUnit
import app.light.wallet.ui.copyToClipboard
import app.light.wallet.ui.expiresIn
import app.light.wallet.ui.formatAmount
import app.light.wallet.ui.formatAmountFull
import app.light.wallet.ui.formatUnixTime
import app.light.wallet.ui.qrBitmap
import app.light.wallet.ui.shortId
import app.light.wallet.ui.theme.MonoFont
import app.light.wallet.ui.theme.SpaceGrotesk
import app.light.wallet.ui.theme.Tokens
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SheetHost(
    repository: WalletRepository,
    sheet: WalletSheet?,
    onClose: () -> Unit,
    onOpenSheet: (WalletSheet) -> Unit,
    onWalletWiped: () -> Unit = {},
    onPaymentStarted: (Long) -> Unit = {},
) {
    if (sheet == null) return
    // The sheet renders in its OWN window, which the Activity's FLAG_SECURE does
    // not cover. Key on `secure` so entering the seed sheet always builds a
    // fresh, secure-born window — even if a future change opens it from within
    // another live sheet (a plain content-swap would otherwise keep the old,
    // non-secure window).
    val secure = sheet is WalletSheet.Seed
    androidx.compose.runtime.key(secure) {
    ModalBottomSheet(
        onDismissRequest = onClose,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = Tokens.Sheet,
        properties = ModalBottomSheetProperties(
            securePolicy = if (secure)
                androidx.compose.ui.window.SecureFlagPolicy.SecureOn
            else
                androidx.compose.ui.window.SecureFlagPolicy.Inherit,
        ),
        dragHandle = {
            Box(
                Modifier.padding(top = 14.dp, bottom = 0.dp).size(width = 40.dp, height = 4.dp)
                    .background(Color(0x26FFFFFF), RoundedCornerShape(999.dp)),
            )
        },
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(top = 14.dp, bottom = 40.dp),
        ) {
            when (sheet) {
                is WalletSheet.Receive -> ReceiveSheet(repository, onClose)
                is WalletSheet.SendChain -> SendChainSheet(repository, onClose)
                is WalletSheet.NewInvoice -> NewInvoiceSheet(repository, onOpenSheet, onClose)
                is WalletSheet.NewInvoiceResult -> InvoiceResultSheet(sheet, onClose)
                is WalletSheet.Pay -> PaySheet(repository, sheet.prefill, onPaymentStarted, onClose)
                is WalletSheet.OpenChannel -> OpenChannelSheet(repository, onClose)
                is WalletSheet.InvoiceDetail -> InvoiceDetailSheet(repository, sheet, onClose)
                is WalletSheet.PaymentDetail -> PaymentDetailSheet(repository, sheet, onClose)
                is WalletSheet.ActivePaymentDetail -> ActivePaymentSheet(repository, sheet.paymentId, onClose)
                is WalletSheet.ChannelDetail -> ChannelDetailSheet(repository, sheet, onClose)
                is WalletSheet.NodeInfoSheet -> NodeSheet(repository, onClose)
                is WalletSheet.Seed -> SeedSheet(repository, onClose)
                is WalletSheet.DropWallet -> DropSheet(repository, onCancel = onClose) { onClose(); onWalletWiped() }
            }
        }
    }
    }
}

@Composable
private fun SheetTitle(text: String, onClose: (() -> Unit)? = null, badge: String? = null) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(text, style = MaterialTheme.typography.titleMedium)
        if (badge != null) {
            Text(
                badge,
                style = MaterialTheme.typography.labelMedium.copy(fontFamily = MonoFont, fontSize = 11.5.sp),
                color = Tokens.Accent,
                modifier = Modifier
                    .padding(start = 10.dp)
                    .background(Tokens.Accent.copy(alpha = .08f), RoundedCornerShape(999.dp))
                    .border(1.dp, Tokens.Accent.copy(alpha = .25f), RoundedCornerShape(999.dp))
                    .padding(horizontal = 11.dp, vertical = 4.dp),
            )
        }
        androidx.compose.foundation.layout.Spacer(Modifier.weight(1f))
        if (onClose != null) {
            Box(
                modifier = Modifier
                    .size(30.dp)
                    .background(Color(0x12FFFFFF), androidx.compose.foundation.shape.CircleShape)
                    .noRipple(onClick = onClose),
                contentAlignment = Alignment.Center,
            ) {
                Text("✕", color = Tokens.TextMid, style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

@Composable
private fun FieldLabel(text: String, topPadding: Int = 4) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp, fontWeight = FontWeight.Bold),
        color = Tokens.Dim,
        modifier = Modifier.padding(top = topPadding.dp, bottom = 8.dp),
    )
}

@Composable
private fun DesignField(
    value: String,
    onValue: (String) -> Unit,
    placeholder: String,
    mono: Boolean = false,
    numeric: Boolean = false,
    big: Boolean = false,
    lines: Int = 1,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValue,
        placeholder = { Text(placeholder, color = Tokens.Faint) },
        minLines = lines,
        maxLines = if (lines > 1) lines + 1 else 1,
        keyboardOptions = if (numeric) KeyboardOptions(keyboardType = KeyboardType.Number) else KeyboardOptions.Default,
        textStyle = when {
            big -> TextStyle(fontFamily = SpaceGrotesk, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, color = Tokens.Text)
            mono -> TextStyle(fontFamily = MonoFont, fontSize = 12.sp, color = Tokens.TextMid, lineHeight = 18.sp)
            else -> TextStyle(fontFamily = MaterialTheme.typography.bodyLarge.fontFamily, fontSize = 14.sp, color = Tokens.Text)
        },
        shape = RoundedCornerShape(13.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedContainerColor = Tokens.CardDeep,
            unfocusedContainerColor = Tokens.CardDeep,
            focusedBorderColor = Tokens.Accent,
            unfocusedBorderColor = Color(0x17FFFFFF),
            cursorColor = Tokens.Accent,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun QrBox(data: String, sizeDp: Int = 188) {
    val bmp = remember(data) { qrBitmap(data) }
    if (bmp != null) {
        Box(
            modifier = Modifier.background(Color.White, RoundedCornerShape(18.dp)).padding(12.dp),
        ) {
            Image(bmp, contentDescription = "QR", modifier = Modifier.size(sizeDp.dp))
        }
    }
}

// ─────────────────────────── Receive (on-chain) ───────────────────────────

@Composable
private fun ReceiveSheet(repository: WalletRepository, onClose: () -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var address by remember { mutableStateOf<String?>(null) }
    var error by remember { mutableStateOf<String?>(null) }

    fun generate() {
        scope.launch {
            runCatching { repository.requireNode().newAddress("bech32") }
                .onSuccess { address = it.bech32 }
                .onFailure { error = it.message }
        }
    }

    androidx.compose.runtime.LaunchedEffect(Unit) { generate() }

    SheetTitle("Receive bitcoin", onClose)
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        address?.let { addr ->
            QrBox(addr.uppercase())
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Tokens.Field, RoundedCornerShape(14.dp))
                    .border(1.dp, Tokens.Border, RoundedCornerShape(14.dp))
                    .noRipple { copyToClipboard(context, "Address", addr) }
                    .padding(horizontal = 15.dp, vertical = 13.dp),
            ) {
                Text(
                    addr,
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = MonoFont, fontSize = 12.sp),
                    color = Tokens.TextMid, modifier = Modifier.weight(1f),
                )
            }
            Text(
                "bech32 · newaddr · a fresh address is generated after each use",
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp),
                color = Tokens.Faint,
            )
            app.light.wallet.ui.OutlinePillButton("Generate new address", height = 46) { generate() }
        } ?: run {
            error?.let { Text(it, color = Tokens.Red, style = MaterialTheme.typography.bodySmall) }
                ?: Text("Generating address…", color = Tokens.Dim, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

// ─────────────────────────── Send (on-chain) ───────────────────────────

@Composable
private fun SendChainSheet(repository: WalletRepository, onClose: () -> Unit) {
    val unit = DisplayUnit.from(repository.displayUnit)
    val scope = rememberCoroutineScope()
    var addr by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var sendAll by remember { mutableStateOf(false) }
    var feerate by remember { mutableStateOf("normal") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var txid by remember { mutableStateOf<String?>(null) }

    SheetTitle("Send on-chain", onClose)
    txid?.let {
        Text("Broadcast ✓", style = MaterialTheme.typography.titleSmall, color = Tokens.Green)
        Text(
            it, style = MaterialTheme.typography.bodySmall.copy(fontFamily = MonoFont, fontSize = 12.5.sp),
            color = Tokens.Dim, modifier = Modifier.padding(top = 8.dp, bottom = 16.dp),
        )
        PillButton("Done", modifier = Modifier.fillMaxWidth()) { onClose() }
        return
    }
    FieldLabel("Destination address")
    DesignField(addr, { addr = it }, "bc1q…", mono = true)
    FieldLabel("Amount (sats)", topPadding = 12)
    DesignField(amount, { amount = it.filter { c -> c.isDigit() }; sendAll = false }, "0", numeric = true, big = true)
    run {
        val funds by repository.funds.collectAsState()
        val available = funds?.let { it.onchainConfirmedMsat / 1000uL } ?: 0uL
        Row(modifier = Modifier.fillMaxWidth().padding(top = 8.dp)) {
            Text(
                "Available: ${formatAmount(available * 1000uL, unit)} ${unit.label}",
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp), color = Tokens.Faint,
                modifier = Modifier.weight(1f),
            )
            Text(
                "Send max",
                style = MaterialTheme.typography.labelMedium.copy(fontSize = 11.5.sp),
                color = Tokens.Accent,
                modifier = Modifier.noRipple { sendAll = true; amount = available.toString() },
            )
        }
    }
    FieldLabel("Feerate", topPadding = 12)
    app.light.wallet.ui.FeerateChips(selected = feerate, onSelect = { feerate = it })
    if (false) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf("slow" to "~1 day", "normal" to "~1 hour", "urgent" to "next block").forEach { (v, sub) ->
            val on = feerate == v
            Column(
                modifier = Modifier
                    .weight(1f)
                    .background(if (on) Tokens.Accent.copy(alpha = .1f) else Tokens.CardDeep, RoundedCornerShape(12.dp))
                    .border(1.dp, if (on) Tokens.Accent.copy(alpha = .4f) else Color(0x17FFFFFF), RoundedCornerShape(12.dp))
                    .noRipple { feerate = v }
                    .padding(vertical = 10.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text(v, style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp), color = if (on) Tokens.Accent else Tokens.TextMid)
                Text(sub, style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp), color = Tokens.Faint, modifier = Modifier.padding(top = 2.dp))
            }
        }
    }
    error?.let { Text(it, color = Tokens.Red, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 10.dp)) }
    PillButton(
        if (busy) "Broadcasting…" else "Send on-chain",
        modifier = Modifier.fillMaxWidth().padding(top = 18.dp),
        enabled = !busy && addr.isNotBlank() && amount.toULongOrNull() != null,
    ) {
        busy = true; error = null
        scope.launch {
            runCatching {
                repository.requireNode().withdraw(
                    WithdrawParams(
                        destination = addr.trim(),
                        amountSat = if (sendAll) 0uL else amount.toULong(),
                        all = sendAll, minconf = null, feerate = feerate,
                    ),
                )
            }.onSuccess { txid = it.txid }.onFailure { error = it.message }
            busy = false
        }
    }
}

// ─────────────────────────── New invoice ───────────────────────────

@Composable
private fun NewInvoiceSheet(repository: WalletRepository, onOpenSheet: (WalletSheet) -> Unit, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var anyAmount by remember { mutableStateOf(false) }
    var amount by remember { mutableStateOf("") }
    var desc by remember { mutableStateOf("") }
    var expD by remember { mutableStateOf("7") }
    var expH by remember { mutableStateOf("0") }
    var expM by remember { mutableStateOf("0") }
    var showAdv by remember { mutableStateOf(false) }
    var customLabel by remember { mutableStateOf("") }
    var cltv by remember { mutableStateOf("") }
    var fallback by remember { mutableStateOf("") }
    var preimageAuto by remember { mutableStateOf(true) }
    var preimageHex by remember { mutableStateOf("") }
    var exposeMode by remember { mutableStateOf("default") } // default | scids
    var exposeScids by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    SheetTitle("Create invoice", onClose)
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(
            "Amount (sats)",
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp, fontWeight = FontWeight.Bold),
            color = Tokens.Dim, modifier = Modifier.weight(1f),
        )
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            modifier = Modifier.noRipple { anyAmount = !anyAmount },
        ) {
            app.light.wallet.ui.DesignSwitch(checked = anyAmount) { anyAmount = !anyAmount }
            Text(
                "Any amount",
                style = MaterialTheme.typography.labelMedium.copy(fontSize = 11.5.sp),
                color = Tokens.TextMid,
            )
        }
    }
    if (!anyAmount) {
        Box(Modifier.padding(top = 8.dp)) {
            DesignField(amount, { amount = it.filter { c -> c.isDigit() } }, "25 000", numeric = true, big = true)
        }
    }
    FieldLabel("Description", topPadding = 12)
    DesignField(desc, { desc = it }, "What is this for?")
    FieldLabel("Expiry", topPadding = 12)
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        listOf(Triple("Days", expD) { v: String -> expD = v },
               Triple("Hours", expH) { v: String -> expH = v },
               Triple("Minutes", expM) { v: String -> expM = v }).forEach { (label, value, setter) ->
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(label, style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
                DesignField(value, { setter(it.filter { c -> c.isDigit() }) }, "0", numeric = true)
            }
        }
    }
    Text(
        if (showAdv) "Advanced ▲" else "Advanced ▼",
        style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp),
        color = Tokens.Accent,
        modifier = Modifier.padding(top = 10.dp).noRipple { showAdv = !showAdv },
    )
    if (showAdv) {
        Row(modifier = Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("Label", style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
                DesignField(customLabel, { customLabel = it }, "auto", mono = true)
            }
            Column(modifier = Modifier.width(110.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("CLTV", style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
                DesignField(cltv, { cltv = it.filter { c -> c.isDigit() } }, "18", numeric = true)
            }
        }
        Column(modifier = Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Fallback address (optional)", style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
            DesignField(fallback, { fallback = it }, "bc1q…", mono = true)
        }
        Row(modifier = Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Preimage",
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold),
                color = Tokens.Faint, modifier = Modifier.weight(1f),
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(7.dp),
                modifier = Modifier.noRipple { preimageAuto = !preimageAuto },
            ) {
                app.light.wallet.ui.DesignSwitch(checked = preimageAuto) { preimageAuto = !preimageAuto }
                Text("Auto-generate", style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp), color = Tokens.TextMid)
            }
        }
        if (preimageAuto) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 6.dp)
                    .background(Color(0x08FFFFFF), RoundedCornerShape(11.dp))
                    .border(1.dp, Color(0x1AFFFFFF), RoundedCornerShape(11.dp))
                    .padding(horizontal = 12.dp, vertical = 10.dp),
            ) {
                Text(
                    "Random 32-byte preimage generated by the node",
                    style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontFamily = FontFamily.Monospace),
                    color = Tokens.Faint,
                )
            }
        } else {
            Box(Modifier.padding(top = 6.dp)) {
                DesignField(preimageHex, { preimageHex = it.trim() }, "64 hex chars", mono = true)
            }
        }
        Text(
            "Expose private channels",
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold),
            color = Tokens.Faint, modifier = Modifier.padding(top = 10.dp, bottom = 6.dp),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("default" to "Default", "true" to "True", "false" to "False", "scids" to "SCIDs").forEach { (v, label) ->
                val on = exposeMode == v
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .background(if (on) Tokens.Accent.copy(alpha = .1f) else Tokens.CardDeep, RoundedCornerShape(11.dp))
                        .border(1.dp, if (on) Tokens.Accent.copy(alpha = .4f) else Color(0x17FFFFFF), RoundedCornerShape(11.dp))
                        .noRipple { exposeMode = v }
                        .padding(vertical = 9.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(label, style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp), color = if (on) Tokens.Accent else Tokens.Dim)
                }
            }
        }
        if (exposeMode == "scids") {
            Box(Modifier.padding(top = 6.dp)) {
                DesignField(exposeScids, { exposeScids = it }, "848291x1204x1, 851002x88x0", mono = true)
            }
        }
        Text(
            "Boolean or a list of short_channel_ids — picking one form rules out the others",
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp),
            color = Tokens.Faint, modifier = Modifier.padding(top = 6.dp),
        )
    }
    error?.let { Text(it, color = Tokens.Red, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 10.dp)) }
    PillButton(
        if (busy) "Creating…" else "Create invoice",
        modifier = Modifier.fillMaxWidth().padding(top = 18.dp),
        enabled = !busy && (anyAmount || amount.toULongOrNull() != null),
    ) {
        busy = true; error = null
        scope.launch {
            val expiry = (expD.toULongOrNull() ?: 0uL) * 86400uL +
                (expH.toULongOrNull() ?: 0uL) * 3600uL + (expM.toULongOrNull() ?: 0uL) * 60uL
            runCatching {
                repository.createInvoice(
                    CreateInvoiceParams(
                        amountMsat = if (anyAmount) null else amount.toULong() * 1000uL,
                        description = desc,
                        label = customLabel.ifBlank { "lightapp-${System.currentTimeMillis()}" },
                        expiry = if (expiry == 0uL) null else expiry,
                        fallbacks = listOf(fallback).filter { it.isNotBlank() },
                        preimageHex = if (!preimageAuto) preimageHex.ifBlank { null } else null,
                        cltv = cltv.toUIntOrNull(),
                        deschashonly = null,
                        // gRPC only carries scid arrays; True = every private
                        // channel we know, False = a filter matching nothing.
                        exposeprivatechannels = when (exposeMode) {
                            "scids" -> exposeScids.split(",").map { it.trim() }.filter { it.isNotEmpty() }
                            "true" -> repository.channels.value.orEmpty()
                                .filter { it.isPrivate == true }
                                .mapNotNull { it.shortChannelId }
                            "false" -> listOf("0x0x0")
                            else -> emptyList()
                        },
                    ),
                )
            }.onSuccess {
                onOpenSheet(WalletSheet.NewInvoiceResult(it.bolt11, it.paymentHash, it.expiresAt))
            }.onFailure { error = it.message }
            busy = false
        }
    }
}

@Composable
private fun InvoiceResultSheet(sheet: WalletSheet.NewInvoiceResult, onClose: () -> Unit) {
    val context = LocalContext.current
    SheetTitle("Invoice created", onClose)
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        QrBox(sheet.bolt11.uppercase(), sizeDp = 200)
        Text(
            shortId(sheet.bolt11, 22),
            style = MaterialTheme.typography.bodySmall.copy(fontFamily = MonoFont, fontSize = 12.5.sp),
            color = Tokens.Dim,
        )
        Text("Expires ${formatUnixTime(sheet.expiresAt)}", style = MaterialTheme.typography.bodySmall, color = Tokens.Faint)
        PillButton("Copy invoice", modifier = Modifier.fillMaxWidth(), height = 48) {
            copyToClipboard(context, "Invoice", sheet.bolt11)
        }
    }
}

// ─────────────────────────── Pay (xpay) ───────────────────────────

@Composable
private fun PaySheet(repository: WalletRepository, prefill: String, onPaymentStarted: (Long) -> Unit, onClose: () -> Unit) {
    val unit = DisplayUnit.from(repository.displayUnit)
    val scope = rememberCoroutineScope()
    var inv by remember { mutableStateOf(prefill) }
    var decoded by remember { mutableStateOf<DecodedInvoice?>(null) }
    var showAdv by remember { mutableStateOf(false) }
    var maxFee by remember { mutableStateOf("") }
    var retryFor by remember { mutableStateOf("") }
    var maxDelay by remember { mutableStateOf("") }
    var partial by remember { mutableStateOf("") }
    var layers by remember { mutableStateOf("") }
    var amountOverride by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    var decodeError by remember { mutableStateOf<String?>(null) }
    var decoding by remember { mutableStateOf(false) }

    androidx.compose.runtime.LaunchedEffect(inv) {
        // Reset everything derived from the previous invoice so a stale amount
        // or decode can never be paid against a newly-pasted invoice.
        decoded = null
        decodeError = null
        amountOverride = ""
        decoding = false
        if (inv.trim().length > 20) {
            decoding = true
            kotlinx.coroutines.delay(350) // debounce while pasting/typing
            runCatching { repository.requireNode().decode(inv.trim()) }
                .onSuccess { decoded = it }
                .onFailure { decodeError = it.message ?: "could not decode invoice" }
            decoding = false
        }
    }

    SheetTitle("Pay", onClose, badge = "xpay")
    DesignField(inv, { inv = it }, "lnbc…", mono = true, lines = 3)

    if (decoded == null && decodeError == null && inv.trim().length > 20) {
        Text(
            "Decoding…",
            style = MaterialTheme.typography.bodySmall, color = Tokens.Dim,
            modifier = Modifier.padding(top = 10.dp),
        )
    }
    decodeError?.let {
        Text(
            "Can't decode: $it",
            style = MaterialTheme.typography.bodySmall, color = Tokens.Red,
            modifier = Modifier.padding(top = 10.dp),
        )
    }
    decoded?.let { d ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 12.dp)
                .background(Tokens.Accent.copy(alpha = .05f), RoundedCornerShape(14.dp))
                .border(1.dp, Tokens.Accent.copy(alpha = .18f), RoundedCornerShape(14.dp))
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            DecRow("Amount", if (d.amountMsat != null) formatAmount(d.amountMsat, unit) + " " + unit.label else "any amount")
            DecRow("Description", d.description ?: d.offerDescription ?: "—")
            DecRow("Payee", shortId(d.payee, 10), mono = true)
            DecRow("Expires", expiresIn(d.createdAt?.let { c -> d.expiry?.let { e -> c + e } }), orange = true)
        }
        if (d.amountMsat == null) {
            FieldLabel("Amount to pay (sats)", topPadding = 12)
            DesignField(amountOverride, { amountOverride = it.filter { c -> c.isDigit() } }, "0", numeric = true, big = true)
        }
    }

    Text(
        if (showAdv) "xpay options ▲" else "xpay options ▼",
        style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp),
        color = Tokens.Accent,
        modifier = Modifier.padding(top = 10.dp).noRipple { showAdv = !showAdv },
    )
    if (showAdv) {
        Row(modifier = Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("maxfee (sats)", style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
                DesignField(maxFee, { maxFee = it.filter { c -> c.isDigit() } }, "auto", numeric = true)
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("retry_for (s)", style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
                DesignField(retryFor, { retryFor = it.filter { c -> c.isDigit() } }, "60", numeric = true)
            }
        }
        Row(modifier = Modifier.padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("maxdelay", style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
                DesignField(maxDelay, { maxDelay = it.filter { c -> c.isDigit() } }, "", numeric = true)
            }
            Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                Text("partial_msat", style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
                DesignField(partial, { partial = it.filter { c -> c.isDigit() } }, "", numeric = true)
            }
        }
        Column(modifier = Modifier.padding(top = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("layers (askrene, comma-separated)", style = MaterialTheme.typography.bodySmall.copy(fontSize = 10.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Faint)
            DesignField(layers, { layers = it }, "", mono = true)
        }
    }

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 12.dp)
            .background(Tokens.Orange.copy(alpha = .06f), RoundedCornerShape(12.dp))
            .border(1.dp, Tokens.Orange.copy(alpha = .2f), RoundedCornerShape(12.dp))
            .padding(horizontal = 14.dp, vertical = 10.dp),
    ) {
        Text(
            "Payment runs in the background — keep using the app while it routes.",
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp, lineHeight = 17.sp),
            color = Tokens.OrangeSoft,
        )
    }
    error?.let { Text(it, color = Tokens.Red, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 10.dp)) }

    val amountKnown = decoded?.amountMsat != null || amountOverride.toULongOrNull() != null
    val payMsat = decoded?.amountMsat ?: amountOverride.toULongOrNull()?.times(1000uL)
    // Never pay until decode of the *current* invoice text has finished.
    val payEnabled = inv.isNotBlank() && decoded != null && !decoding && amountKnown
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 14.dp)
            .height(52.dp)
            .background(
                if (payEnabled) Tokens.Accent else Tokens.Accent.copy(alpha = .3f),
                RoundedCornerShape(999.dp),
            )
            .noRipple(enabled = payEnabled) {
                error = null
                val id = repository.startPayment(
                    PayCommand.Xpay(
                        XpayParams(
                            invstring = inv.trim(),
                            amountMsat = if (decoded?.amountMsat == null) amountOverride.toULongOrNull()?.times(1000uL) else null,
                            maxfeeMsat = maxFee.toULongOrNull()?.times(1000uL),
                            layers = layers.split(",").map { it.trim() }.filter { it.isNotEmpty() },
                            retryFor = retryFor.toUIntOrNull(),
                            partialMsat = partial.toULongOrNull(),
                            maxdelay = maxDelay.toUIntOrNull(),
                        ),
                    ),
                    description = decoded?.description ?: decoded?.offerDescription,
                )
                onPaymentStarted(id)
            },
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        androidx.compose.material3.Icon(
            androidx.compose.material.icons.Icons.Filled.Bolt, null,
            tint = Tokens.AccentInk,
            modifier = Modifier.size(15.dp),
        )
        Text(
            "Pay" + (payMsat?.let { " " + formatAmount(it, unit) + " " + unit.label } ?: ""),
            style = MaterialTheme.typography.labelLarge,
            color = Tokens.AccentInk,
            maxLines = 1,
            modifier = Modifier.padding(start = 6.dp),
        )
    }
}

@Composable
private fun DecRow(k: String, v: String, mono: Boolean = false, orange: Boolean = false) {
    Row(modifier = Modifier.fillMaxWidth()) {
        Text(k, style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp), color = Tokens.Faint)
        Text(
            v,
            style = MaterialTheme.typography.bodySmall.copy(
                fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                fontFamily = if (mono) MonoFont else MaterialTheme.typography.bodySmall.fontFamily,
            ),
            color = if (orange) Tokens.Orange else Tokens.TextMid,
            modifier = Modifier.weight(1f),
            textAlign = androidx.compose.ui.text.style.TextAlign.End,
        )
    }
}

// ─────────────────────────── Open channel ───────────────────────────

@Composable
private fun OpenChannelSheet(repository: WalletRepository, onClose: () -> Unit) {
    val scope = rememberCoroutineScope()
    var peer by remember { mutableStateOf("") }
    var amount by remember { mutableStateOf("") }
    var minconf by remember { mutableStateOf("") }
    var feerate by remember { mutableStateOf("") }
    var announce by remember { mutableStateOf(true) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var result by remember { mutableStateOf<String?>(null) }

    SheetTitle("Open channel", onClose)
    result?.let {
        Text("Channel funding broadcast ✓", style = MaterialTheme.typography.titleSmall, color = Tokens.Green)
        Text(it, style = MaterialTheme.typography.bodySmall.copy(fontFamily = MonoFont, fontSize = 12.5.sp), color = Tokens.Dim, modifier = Modifier.padding(top = 8.dp, bottom = 16.dp))
        PillButton("Done", modifier = Modifier.fillMaxWidth()) { onClose() }
        return
    }
    FieldLabel("Peer connect string")
    DesignField(peer, { peer = it }, "nodeid@host:port", mono = true, lines = 2)
    Row(modifier = Modifier.padding(top = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Amount (sats)", style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Dim)
            DesignField(amount, { amount = it.filter { c -> c.isDigit() } }, "1 000 000", numeric = true, big = true)
        }
        Column(modifier = Modifier.width(110.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text("Min conf", style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp, fontWeight = FontWeight.Bold), color = Tokens.Dim)
            DesignField(minconf, { minconf = it.filter { c -> c.isDigit() } }, "1", numeric = true)
        }
    }
    FieldLabel("Feerate", topPadding = 12)
    app.light.wallet.ui.FeerateChips(selected = feerate.ifBlank { "normal" }, onSelect = { feerate = it })
    Row(
        modifier = Modifier.padding(top = 12.dp).noRipple { announce = !announce },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        app.light.wallet.ui.DesignSwitch(checked = announce) { announce = !announce }
        Text("Announce", style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp), color = Tokens.TextMid)
        Text("public channel, visible in gossip", style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp), color = Tokens.Faint)
    }
    error?.let { Text(it, color = Tokens.Red, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 10.dp)) }
    PillButton(
        if (busy) "Opening…" else "Connect & fund channel",
        modifier = Modifier.fillMaxWidth().padding(top = 18.dp),
        enabled = !busy && peer.isNotBlank() && amount.toULongOrNull() != null,
    ) {
        busy = true; error = null
        scope.launch {
            runCatching {
                val node = repository.requireNode()
                val nodeId = if ("@" in peer) {
                    val (id, hostPort) = peer.trim().split("@", limit = 2)
                    val host = hostPort.substringBeforeLast(":")
                    val port = hostPort.substringAfterLast(":").toUIntOrNull()
                    node.connectPeer(id.trim(), host, port)
                    id.trim()
                } else peer.trim()
                node.openChannel(
                    OpenChannelParams(
                        peerId = nodeId, amountSat = amount.toULong(), all = false,
                        feerate = feerate.ifBlank { null }, announce = announce, pushMsat = null,
                        closeTo = null, minconf = minconf.toUIntOrNull(), mindepth = null, reserveMsat = null,
                    ),
                )
            }.onSuccess { result = "txid ${it.txid}" }.onFailure { error = it.message }
            busy = false
        }
    }
    Text(
        "connect → fundchannel",
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.sp, fontFamily = FontFamily.Monospace),
        color = Tokens.Faint,
        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
    )
}

// ─────────────────────────── Details ───────────────────────────

@Composable
private fun InvoiceDetailSheet(repository: WalletRepository, sheet: WalletSheet.InvoiceDetail, onClose: () -> Unit) {
    val context = LocalContext.current
    val inv = sheet.invoice
    val unit = DisplayUnit.from(repository.displayUnit)
    SheetTitle("Invoice", onClose)
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        if (inv.status == "unpaid" && inv.bolt11 != null) {
            QrBox(inv.bolt11!!.uppercase(), sizeDp = 164)
        }
        Text(
            formatAmount(inv.amountMsat, unit) + " " + unit.label,
            style = MaterialTheme.typography.displaySmall.copy(fontSize = 30.sp),
            color = app.light.wallet.ui.statusColor(inv.status),
            modifier = Modifier.padding(vertical = 12.dp),
        )
    }
    KvPanel(
        listOfNotNull(
            Triple("Status", inv.status, false),
            Triple("Description", inv.description ?: "—", false),
            Triple("Label", inv.label, true),
            Triple("Payment hash", inv.paymentHash, true),
            inv.paymentPreimage?.let { Triple("Preimage", it, true) },
            Triple("Expires", formatUnixTime(inv.expiresAt), false),
            inv.paidAt?.let { Triple("Paid at", formatUnixTime(it), false) },
            inv.amountReceivedMsat?.let { Triple("Received", formatAmountFull(it, unit), false) },
        ),
    )
    inv.bolt11?.let {
        app.light.wallet.ui.OutlinePillButton("Copy bolt11", modifier = Modifier.fillMaxWidth().padding(top = 14.dp)) {
            copyToClipboard(context, "Invoice", it)
        }
    }
}

@Composable
private fun PaymentDetailSheet(repository: WalletRepository, sheet: WalletSheet.PaymentDetail, onClose: () -> Unit) {
    val p = sheet.pay
    val unit = DisplayUnit.from(repository.displayUnit)
    SheetTitle("Payment", onClose)
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        Text(
            "−" + formatAmount(p.amountMsat, unit) + " " + unit.label,
            style = MaterialTheme.typography.displaySmall.copy(fontSize = 30.sp),
            color = app.light.wallet.ui.statusColor(p.status),
            modifier = Modifier.padding(bottom = 12.dp),
        )
    }
    val fee = if (p.amountSentMsat != null && p.amountMsat != null &&
        p.amountSentMsat!! >= p.amountMsat!!
    ) p.amountSentMsat!! - p.amountMsat!! else null
    KvPanel(
        listOfNotNull(
            Triple("Status", p.status, false),
            Triple("Description", p.description?.ifBlank { null } ?: "—", !p.description.isNullOrBlank()),
            Triple("Destination", p.destination ?: "—", true),
            Triple("Fee", formatAmountFull(fee, unit), false),
            Triple("Created", formatUnixTime(p.createdAt), false),
            p.completedAt?.let { Triple("Completed", formatUnixTime(it), false) },
            Triple("Payment hash", p.paymentHash, true),
            p.preimage?.let { Triple("Preimage", it, true) },
            p.numberOfParts?.let { Triple("Parts", it.toString(), false) },
        ),
    )
}

@Composable
private fun ActivePaymentSheet(repository: WalletRepository, paymentId: Long, onClose: () -> Unit) {
    // Live: keeps rendering the latest state of this payment while it routes.
    val active by repository.activePayments.collectAsState()
    val unit = DisplayUnit.from(repository.displayUnit)
    val p = active.firstOrNull { it.id == paymentId }
    SheetTitle("Payment", onClose)
    if (p == null) {
        Text("Payment record not found.", style = MaterialTheme.typography.bodyMedium, color = Tokens.Dim)
        return
    }
    val statusColor = when (p.status) {
        ActivePaymentStatus.PAYING -> Tokens.Orange
        ActivePaymentStatus.PENDING -> Tokens.Orange
        ActivePaymentStatus.COMPLETE -> Tokens.Green
        ActivePaymentStatus.FAILED -> Tokens.Red
    }
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth().padding(bottom = 16.dp),
    ) {
        if (p.status == ActivePaymentStatus.PAYING) {
            androidx.compose.material3.CircularProgressIndicator(
                color = Tokens.Orange, strokeWidth = 2.dp,
                modifier = Modifier.padding(bottom = 12.dp).size(28.dp),
            )
        }
        Text(
            p.amountMsat?.let { "−" + formatAmount(it, unit) + " " + unit.label }
                ?: when (p.status) {
                    ActivePaymentStatus.PAYING -> "Routing…"
                    ActivePaymentStatus.PENDING -> "Pending — still in flight"
                    ActivePaymentStatus.COMPLETE -> "Paid"
                    ActivePaymentStatus.FAILED -> "Failed"
                },
            style = MaterialTheme.typography.displaySmall.copy(fontSize = 30.sp),
            color = statusColor,
        )
        Text(
            "via xpay" + if (p.status == ActivePaymentStatus.PAYING) " — routing…" else "",
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp), color = Tokens.Faint,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
    KvPanel(
        listOfNotNull(
            Triple("Status", p.status.name.lowercase(), false),
            p.description?.let { Triple("Description", it, false) },
            Triple("Invoice", shortId(p.invstring, 20), true),
            p.feeMsat?.let { Triple("Fee", formatAmountFull(it, unit), false) },
            p.preimage?.let { Triple("Preimage", it, true) },
            p.error?.let { Triple("Error", it, false) },
        ),
        valueColor = { if (it == "Error") Tokens.Red else Tokens.TextMid },
    )
}

@Composable
private fun ChannelDetailSheet(
    repository: WalletRepository,
    sheet: WalletSheet.ChannelDetail,
    onClose: () -> Unit,
) {
    val unit = DisplayUnit.from(repository.displayUnit)
    val scope = rememberCoroutineScope()
    val ch = sheet.channel
    var confirmClose by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var closed by remember { mutableStateOf<String?>(null) }

    SheetTitle(ch.peerAlias?.takeIf { it.isNotBlank() } ?: "Channel", onClose)
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth().padding(bottom = 14.dp)) {
        Text(
            formatAmount(ch.spendableMsat, unit) + " " + unit.label,
            style = MaterialTheme.typography.displaySmall.copy(fontSize = 30.sp),
        )
        Text(
            "spendable of ${formatAmount(ch.totalMsat, unit)} capacity",
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 11.5.sp), color = Tokens.Faint,
            modifier = Modifier.padding(top = 3.dp),
        )
    }
    KvPanel(
        listOfNotNull(
            Triple("Peer", ch.peerId, true),
            Triple("State", ch.state, false),
            Triple("Connected", if (ch.peerConnected) "yes" else "no", false),
            ch.shortChannelId?.let { Triple("Short id", it, true) },
            Triple("Capacity", formatAmountFull(ch.totalMsat, unit), false),
            Triple("Ours", formatAmountFull(ch.toUsMsat, unit), false),
            Triple("Theirs", formatAmountFull(ch.toThemMsat, unit), false),
            Triple("Spendable", formatAmountFull(ch.spendableMsat, unit), false),
            Triple("Receivable", formatAmountFull(ch.receivableMsat, unit), false),
            ch.ourReserveMsat?.let { Triple("Our reserve", formatAmountFull(it, unit), false) },
            ch.feeBaseMsat?.let { Triple("Fee base", formatAmountFull(it, unit), false) },
            ch.feeProportionalMillionths?.let { Triple("Fee ppm", it.toString(), false) },
            Triple("Opener", ch.opener, false),
            ch.fundingTxid?.let { Triple("Funding txid", it, true) },
        ),
    )
    closed?.let {
        Text("Close initiated: $it", color = Tokens.Green, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 12.dp))
        PillButton("Done", modifier = Modifier.fillMaxWidth().padding(top = 12.dp)) { onClose() }
        return
    }
    error?.let { Text(it, color = Tokens.Red, style = MaterialTheme.typography.bodySmall, modifier = Modifier.padding(top = 10.dp)) }
    DangerPillButton(
        when {
            busy -> "Closing…"
            confirmClose -> "Tap again to confirm close"
            else -> "Close channel"
        },
        modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
    ) {
        if (!confirmClose) { confirmClose = true; return@DangerPillButton }
        busy = true; error = null
        scope.launch {
            runCatching {
                repository.requireNode().closeChannel(
                    CloseChannelParams(
                        id = ch.channelId ?: ch.peerId,
                        unilateralTimeout = null, destination = null,
                        feeNegotiationStep = null, forceLeaseClosed = null,
                    ),
                )
            }.onSuccess { closed = it.closeType }.onFailure { error = it.message }
            busy = false
        }
    }
}

@Composable
private fun NodeSheet(repository: WalletRepository, onClose: () -> Unit) {
    val unit = DisplayUnit.from(repository.displayUnit)
    val context = LocalContext.current
    val connState by repository.connState.collectAsState()
    val info = (connState as? ConnState.Connected)?.info
    SheetTitle("Node", onClose)
    if (info == null) {
        Text("Node info is available once connected.", style = MaterialTheme.typography.bodyMedium, color = Tokens.Dim)
        return
    }
    KvPanel(
        listOf(
            Triple("Node ID", info.id, true),
            Triple("Alias", info.alias, false),
            Triple("Network", info.network, false),
            Triple("Block height", info.blockheight.toString(), false),
            Triple("Version", info.version, false),
            Triple("Peers", info.numPeers.toString(), false),
            Triple("Active channels", info.numActiveChannels.toString(), false),
            Triple("Connect string", info.connectString, true),
            Triple("Fees collected", formatAmountFull(info.feesCollectedMsat, unit), false),
        ),
    )
}

@Composable
private fun SeedSheet(repository: WalletRepository, onClose: () -> Unit) {
    val context = LocalContext.current
    var revealed by remember { mutableStateOf(false) }
    // StrongBox decrypt of the mnemonic — off-main, exactly once per open
    // (reading it in composition froze the frame for each recomposition).
    var words by remember { mutableStateOf<List<String>?>(null) }
    androidx.compose.runtime.LaunchedEffect(Unit) {
        words = repository.loadMnemonicWords()
    }
    val loaded = words
    SheetTitle("Recovery phrase", onClose)
    if (loaded == null) {
        Text(
            "Decrypting…",
            style = MaterialTheme.typography.bodySmall, color = Tokens.Dim,
            modifier = Modifier.padding(bottom = 14.dp),
        )
        return
    }
    Text(
        "Anyone with these ${loaded.size} words can take your funds. Reveal only in private.",
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 14.sp, lineHeight = 22.sp),
        color = Tokens.Label,
        modifier = Modifier.padding(bottom = 14.dp),
    )
    app.light.wallet.ui.SeedGrid(words = loaded, revealed = revealed, onReveal = { revealed = true })
    app.light.wallet.ui.OutlinePillButton(
        "Copy seed",
        modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
    ) {
        copyToClipboard(context, "Seed", loaded.joinToString(" "), sensitive = true)
    }
    Text(
        "Reveal requires a private moment — a biometric gate lands before the seed is decrypted in a future release.",
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, lineHeight = 19.sp),
        color = Tokens.Dim,
        modifier = Modifier.padding(top = 12.dp),
    )
}

@Composable
private fun DropSheet(repository: WalletRepository, onCancel: () -> Unit = {}, onWiped: () -> Unit) {
    SheetTitle("Delete wallet data")
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.Red.copy(alpha = .06f), RoundedCornerShape(14.dp))
            .border(1.dp, Tokens.Red.copy(alpha = .25f), RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Text(
            "This wipes the seed, Greenlight certificates and local caches from this device. " +
                "Your node stays scheduled at Greenlight — recover it anytime with the 24 words.",
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 14.sp, lineHeight = 23.sp),
            color = Color(0xFFF8B4B2),
        )
    }
    var armed by remember { mutableStateOf(false) }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 14.dp)
            .height(52.dp)
            .background(Tokens.Red, RoundedCornerShape(999.dp))
            .noRipple {
                if (!armed) armed = true
                else { repository.wipeWallet(); onWiped() }
            },
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (armed) "Tap again to erase" else "Erase wallet data",
            style = MaterialTheme.typography.labelLarge.copy(fontSize = 15.sp),
            color = Color(0xFF2B0705),
        )
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 10.dp)
            .height(48.dp)
            .border(1.dp, Color(0x24FFFFFF), RoundedCornerShape(999.dp))
            .noRipple(onClick = onCancel),
        contentAlignment = Alignment.Center,
    ) {
        Text("Cancel", style = MaterialTheme.typography.labelMedium.copy(fontSize = 14.sp), color = Tokens.TextMid)
    }
}
