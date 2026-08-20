package app.light.wallet.ui.onboarding

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.core.generateMnemonic
import app.light.wallet.core.validateMnemonic
import app.light.wallet.data.WalletRepository
import app.light.wallet.ui.SecureScreen
import app.light.wallet.ui.copyToClipboard
import app.light.wallet.ui.noRipple
import app.light.wallet.ui.PillButton
import app.light.wallet.ui.theme.MonoFont
import app.light.wallet.ui.theme.Tokens
import kotlinx.coroutines.launch

private enum class Step { WELCOME, CREATE, RESTORE, CERTS, REGISTER }

@Composable
fun OnboardingFlow(repository: WalletRepository, onDone: () -> Unit) {
    var step by remember { mutableStateOf(Step.WELCOME) }
    var mnemonic by remember { mutableStateOf("") }
    var isRestore by remember { mutableStateOf(false) }
    var certBytes by remember { mutableStateOf<ByteArray?>(null) }
    var keyBytes by remember { mutableStateOf<ByteArray?>(null) }

    // System back mirrors the on-screen Back buttons through the flow.
    androidx.activity.compose.BackHandler(enabled = step != Step.WELCOME) {
        step = when (step) {
            Step.CREATE, Step.RESTORE -> Step.WELCOME
            Step.CERTS -> if (isRestore) Step.RESTORE else Step.CREATE
            Step.REGISTER -> Step.CERTS
            else -> Step.WELCOME
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Tokens.Bg)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp)
            .padding(top = 78.dp, bottom = 40.dp),
    ) {
        when (step) {
            Step.WELCOME -> Welcome(
                onCreate = {
                    isRestore = false
                    mnemonic = runCatching { generateMnemonic() }.getOrDefault("")
                    step = Step.CREATE
                },
                onRestore = {
                    isRestore = true
                    // A previously generated (create-flow) seed must never
                    // leak into the restore boxes.
                    mnemonic = ""
                    step = Step.RESTORE
                },
            )
            Step.CREATE -> CreateWallet(mnemonic,
                onNext = { step = Step.CERTS }, onBack = { step = Step.WELCOME })
            Step.RESTORE -> RestoreWallet(mnemonic, { mnemonic = it },
                onNext = { step = Step.CERTS }, onBack = { step = Step.WELCOME })
            Step.CERTS -> Certificates(certBytes, keyBytes, { certBytes = it }, { keyBytes = it },
                onNext = { step = Step.REGISTER },
                onBack = { step = if (isRestore) Step.RESTORE else Step.CREATE })
            Step.REGISTER -> Register(repository, mnemonic, certBytes, keyBytes,
                isRestore, onDone, onBack = { step = Step.CERTS })
        }
    }
}

@Composable
private fun Logo(sizeDp: Int = 88, radius: Int = 22) {
    androidx.compose.foundation.Image(
        painter = androidx.compose.ui.res.painterResource(app.light.wallet.R.drawable.logo_lightapp),
        contentDescription = "LightApp",
        modifier = Modifier
            .size(sizeDp.dp)
            .clip(RoundedCornerShape(radius.dp)),
    )
}

@Composable
private fun GhostButton(text: String, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        modifier = modifier
            .height(54.dp)
            .border(1.dp, Color(0x24FFFFFF), RoundedCornerShape(999.dp))
            .noRipple(enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold),
            color = Tokens.TextMid,
        )
    }
}

@Composable
private fun ObField(
    value: String, onValue: (String) -> Unit, placeholder: String,
    mono: Boolean = false, lines: Int = 1,
) {
    OutlinedTextField(
        value = value, onValueChange = onValue,
        placeholder = { Text(placeholder, color = Tokens.Faint) },
        minLines = lines, maxLines = lines + 1,
        textStyle = if (mono) TextStyle(fontFamily = MonoFont, fontSize = 13.sp, color = Tokens.Text, lineHeight = 20.sp)
        else TextStyle(fontSize = 14.sp, color = Tokens.Text),
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
private fun Welcome(onCreate: () -> Unit, onRestore: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 60.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        Logo()
        Text("LightApp", style = MaterialTheme.typography.headlineSmall.copy(fontSize = 34.sp))
        Text(
            "A full Core Lightning node in your pocket, powered by Greenlight. Built by Engineers for Engineers.",
            style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, lineHeight = 23.sp),
            color = Tokens.Label,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
    Spacer(Modifier.height(120.dp))
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        PillButton("Create new wallet", modifier = Modifier.fillMaxWidth(), height = 54) { onCreate() }
        GhostButton("Restore from seed", modifier = Modifier.fillMaxWidth()) { onRestore() }
        OpenSourceNote(
            "LightApp is open source. We recommend double-checking the code at ",
            " before using the application.",
        )
    }
}

/** Open-source disclaimer with the repo URL highlighted; tapping opens GitHub. */
@Composable
private fun OpenSourceNote(prefix: String, suffix: String) {
    val context = LocalContext.current
    val text = androidx.compose.ui.text.buildAnnotatedString {
        append(prefix)
        withStyle(
            androidx.compose.ui.text.SpanStyle(
                color = Tokens.Accent, fontWeight = FontWeight.Bold,
                fontFamily = app.light.wallet.ui.theme.MonoFont,
            ),
        ) { append("github.com/olegfomenko/light-app") }
        append(suffix)
    }
    Text(
        text,
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, lineHeight = 20.sp),
        color = Tokens.Faint,
        textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 8.dp)
            .noRipple {
                context.startActivity(
                    android.content.Intent(
                        android.content.Intent.ACTION_VIEW,
                        android.net.Uri.parse("https://github.com/olegfomenko/light-app"),
                    ),
                )
            },
    )
}

@Composable
private fun CreateWallet(
    mnemonic: String,
    onNext: () -> Unit, onBack: () -> Unit,
) {
    val context = LocalContext.current
    var revealed by remember { mutableStateOf(false) }
    SecureScreen()
    Text("Your recovery phrase", style = MaterialTheme.typography.headlineSmall)
    Text(
        "This BIP39 seed derives your node identity and on-chain keys. Write the ${mnemonic.split(" ").size} words down, in order, on paper.",
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 14.sp, lineHeight = 21.sp),
        color = Tokens.Label, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp),
    )
    app.light.wallet.ui.SeedGrid(
        words = mnemonic.split(" "),
        revealed = revealed,
        onReveal = { revealed = true },
    )
    Text(
        "Write these words down — they are the only way to recover your wallet. They never leave this device.",
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.5.sp, lineHeight = 20.sp),
        color = Tokens.TextMid, modifier = Modifier.padding(top = 14.dp),
    )
    app.light.wallet.ui.SoftPillButton(
        "Copy seed",
        modifier = Modifier.fillMaxWidth().padding(top = 14.dp),
        height = 46,
    ) {
        copyToClipboard(context, "Seed", mnemonic, sensitive = true)
    }
    PillButton("I wrote it down", modifier = Modifier.fillMaxWidth().padding(top = 20.dp), enabled = revealed, height = 54) { onNext() }
    GhostButton("Back", modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) { onBack() }
}

@Composable
private fun RestoreWallet(
    mnemonic: String, onMnemonic: (String) -> Unit,
    onNext: () -> Unit, onBack: () -> Unit,
) {
    // 24 separate boxes; pasting a whole phrase into any box distributes the
    // words across the following boxes (12-word seeds also validate).
    var words by remember {
        mutableStateOf(List(24) { i -> mnemonic.split(" ").getOrElse(i) { "" }.trim() })
    }

    fun update(index: Int, raw: String) {
        val parts = raw.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
        words = if (parts.size > 1) {
            // A multi-word paste is the whole phrase: fill from the first box
            // regardless of which box received it, so nothing is truncated or
            // left stale in earlier boxes.
            List(24) { i -> parts.getOrElse(i) { "" }.lowercase() }
        } else {
            List(24) { i -> if (i == index) raw.trim().lowercase() else words[i] }
        }
        onMnemonic(words.filter { it.isNotEmpty() }.joinToString(" "))
    }

    val filled = words.count { it.isNotEmpty() }
    val phrase = words.filter { it.isNotEmpty() }.joinToString(" ")
    val complete = (filled == 24 || (filled == 12 && words.drop(12).all { it.isEmpty() } &&
        words.take(12).all { it.isNotEmpty() }))
    val valid = complete && validateMnemonic(phrase)

    SecureScreen()
    Text("Restore from seed", style = MaterialTheme.typography.headlineSmall)
    Text(
        "Enter your 12 or 24 word recovery phrase. Paste the whole phrase into any field to fill them all.",
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 14.sp, lineHeight = 21.sp),
        color = Tokens.Label, modifier = Modifier.padding(top = 8.dp, bottom = 20.dp),
    )
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        words.chunked(2).forEachIndexed { row, pair ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                pair.forEachIndexed { col, word ->
                    val index = row * 2 + col
                    Row(
                        modifier = Modifier
                            .weight(1f)
                            .background(Tokens.Field, RoundedCornerShape(12.dp))
                            .border(
                                1.dp,
                                if (word.isNotEmpty() && !validateWordPrefix(word)) Tokens.Red.copy(alpha = .5f)
                                else Color(0x0FFFFFFF),
                                RoundedCornerShape(12.dp),
                            )
                            .padding(start = 14.dp, end = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            "${index + 1}",
                            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontFamily = MonoFont, fontWeight = FontWeight.SemiBold),
                            color = Tokens.Faint,
                        )
                        androidx.compose.foundation.text.BasicTextField(
                            value = word,
                            onValueChange = { update(index, it) },
                            singleLine = true,
                            textStyle = androidx.compose.ui.text.TextStyle(
                                fontFamily = MonoFont, fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold, color = Tokens.Text,
                            ),
                            cursorBrush = androidx.compose.ui.graphics.SolidColor(Tokens.Accent),
                            modifier = Modifier.weight(1f).padding(vertical = 12.dp, horizontal = 4.dp),
                        )
                    }
                }
            }
        }
    }
    if (complete && !valid) {
        Text(
            "Invalid phrase (checksum failed)",
            color = Tokens.Red, style = MaterialTheme.typography.bodySmall,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
    PillButton("Continue", modifier = Modifier.fillMaxWidth().padding(top = 20.dp), enabled = valid, height = 54) { onNext() }
    GhostButton("Back", modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) { onBack() }
}

/** Cheap per-word sanity check: lowercase a–z only (full checksum runs on the whole phrase). */
private fun validateWordPrefix(word: String): Boolean = word.all { it in 'a'..'z' }

@Composable
private fun Certificates(
    certBytes: ByteArray?, keyBytes: ByteArray?,
    onCert: (ByteArray?) -> Unit, onKey: (ByteArray?) -> Unit,
    onNext: () -> Unit, onBack: () -> Unit,
) {
    val context = LocalContext.current
    fun readUri(uri: Uri?): ByteArray? = uri?.let {
        runCatching { context.contentResolver.openInputStream(it)?.use { s -> s.readBytes() } }.getOrNull()
    }
    val pickCert = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { onCert(readUri(it)) }
    val pickKey = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { onKey(readUri(it)) }

    Text("Greenlight credentials", style = MaterialTheme.typography.headlineSmall)
    val glIntro = androidx.compose.ui.text.buildAnnotatedString {
        append("Upload the developer certificate pair from the ")
        withStyle(androidx.compose.ui.text.SpanStyle(color = Tokens.Accent, fontWeight = FontWeight.Bold)) {
            append("Greenlight console")
        }
        append(". They authorize this app to register and schedule your node.")
    }
    Text(
        glIntro,
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 14.sp, lineHeight = 21.sp),
        color = Tokens.Label,
        modifier = Modifier
            .padding(top = 8.dp, bottom = 22.dp)
            .noRipple {
                context.startActivity(
                    android.content.Intent(
                        android.content.Intent.ACTION_VIEW,
                        android.net.Uri.parse("https://greenlight.blockstream.com/"),
                    ),
                )
            },
    )
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        CertCard("client.crt",
            if (certBytes == null) "Developer certificate · PEM" else "${certBytes.size} bytes loaded",
            certBytes != null) { pickCert.launch(arrayOf("*/*")) }
        CertCard("client-key.pem",
            if (keyBytes == null) "Private key · keep secret" else "${keyBytes.size} bytes loaded",
            keyBytes != null) { pickKey.launch(arrayOf("*/*")) }
    }
    Text(
        "Certificate and key are stored encrypted in the Android Keystore. The files you picked stay where you chose them — keep them safe.",
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, lineHeight = 19.sp),
        color = Tokens.Dim, modifier = Modifier.padding(top = 14.dp),
    )
    PillButton(
        "Continue",
        modifier = Modifier.fillMaxWidth().padding(top = 24.dp),
        enabled = certBytes != null && keyBytes != null, height = 54,
    ) { onNext() }
    GhostButton("Back", modifier = Modifier.fillMaxWidth().padding(top = 10.dp)) { onBack() }
}

@Composable
private fun CertCard(name: String, sub: String, done: Boolean, onClick: () -> Unit) {
    // Dashed border per design (Compose has no dashed border modifier; a
    // PathEffect stroke drawn behind achieves it).
    val borderColor = if (done) Tokens.Green.copy(alpha = .5f) else Color(0x26FFFFFF)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.Field, RoundedCornerShape(16.dp))
            .drawBehind {
                drawRoundRect(
                    color = borderColor,
                    style = androidx.compose.ui.graphics.drawscope.Stroke(
                        width = 1.dp.toPx(),
                        pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(
                            floatArrayOf(10f, 8f),
                        ),
                    ),
                    cornerRadius = androidx.compose.ui.geometry.CornerRadius(16.dp.toPx()),
                )
            }
            .noRipple(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold, fontFamily = MonoFont))
            Text(sub, style = MaterialTheme.typography.bodySmall.copy(fontSize = 13.sp), color = Tokens.Dim, modifier = Modifier.padding(top = 2.dp))
        }
        Text(
            "✓",
            style = MaterialTheme.typography.titleSmall,
            color = if (done) Tokens.Green else Color(0x1AFFFFFF),
        )
    }
}

@Composable
private fun Register(
    repository: WalletRepository,
    mnemonic: String,
    certBytes: ByteArray?, keyBytes: ByteArray?, isRestore: Boolean,
    onDone: () -> Unit, onBack: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var busy by remember { mutableStateOf(false) }
    var step by remember { mutableStateOf(-1) } // -1 idle, 0..2 stages, 3 done
    var error by remember { mutableStateOf<String?>(null) }
    val action = if (isRestore) "Recover node" else "Register node"

    Text(
        if (isRestore) "Recovering your node" else "Registering your node",
        style = MaterialTheme.typography.headlineSmall,
    )
    Text(
        if (isRestore)
            "We'll recover your existing Greenlight node from the seed and issue fresh device credentials for this phone."
        else
            "We'll register a brand-new Core Lightning node for your seed on mainnet. Takes a few seconds.",
        style = MaterialTheme.typography.bodySmall.copy(fontSize = 14.sp, lineHeight = 21.sp),
        color = Tokens.Label, modifier = Modifier.padding(top = 8.dp, bottom = 22.dp),
    )
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        RegRow("Loading credentials", "mTLS keypair → keystore", step, 0)
        RegRow(
            if (isRestore) "scheduler.recover(node)" else "scheduler.register(node)",
            "gl.blckstrm.com:2111", step, 1,
        )
        RegRow("Node scheduled", "signer ready · device credentials stored", step, 2)
    }
    error?.let {
        Text(it, color = Tokens.Red, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(top = 14.dp))
    }
    Spacer(Modifier.height(24.dp))
    OpenSourceNote("Before you continue: this app is open source — double-check the code at ", ".")
    Spacer(Modifier.height(14.dp))
    PillButton(action, modifier = Modifier.fillMaxWidth(), enabled = !busy, height = 54) {
        busy = true; error = null; step = 0
        scope.launch {
            try {
                step = 1
                repository.setupWallet(
                    mnemonic = mnemonic.trim(), passphrase = "", network = "bitcoin",
                    developerCert = certBytes ?: ByteArray(0),
                    developerKey = keyBytes ?: ByteArray(0),
                    restore = isRestore,
                )
                step = 3
                onDone()
            } catch (e: Exception) {
                error = e.message ?: "registration failed"
                step = -1
            } finally {
                busy = false
            }
        }
    }
    GhostButton("Back", modifier = Modifier.fillMaxWidth().padding(top = 10.dp), enabled = !busy) { onBack() }
}

@Composable
private fun RegRow(title: String, sub: String, step: Int, index: Int) {
    val done = step > index
    val active = step == index || (index == 1 && step == 1)
    val ringColor = when {
        done -> Tokens.Accent
        active -> Tokens.Accent.copy(alpha = .5f)
        else -> Color(0x1FFFFFFF)
    }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Tokens.Field, RoundedCornerShape(14.dp))
            .border(1.dp, Color(0x0FFFFFFF), RoundedCornerShape(14.dp))
            .padding(horizontal = 16.dp, vertical = 15.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Box(
            modifier = Modifier
                .size(26.dp)
                .border(2.dp, ringColor, androidx.compose.foundation.shape.CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            when {
                done -> Text("✓", color = Tokens.Accent, style = MaterialTheme.typography.labelMedium)
                active -> CircularProgressIndicator(color = Tokens.Accent, strokeWidth = 2.dp, modifier = Modifier.size(13.dp))
            }
        }
        Column {
            Text(
                title,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold),
                color = if (done || active) Tokens.Text else Tokens.Faint,
            )
            Text(
                sub,
                style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp, fontFamily = MonoFont),
                color = Tokens.Dim, modifier = Modifier.padding(top = 1.dp),
            )
        }
    }
}
