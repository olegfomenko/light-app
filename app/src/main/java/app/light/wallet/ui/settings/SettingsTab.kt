package app.light.wallet.ui.settings

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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.light.wallet.data.WalletRepository
import app.light.wallet.ui.noRipple
import app.light.wallet.ui.copyToClipboard
import app.light.wallet.ui.sheets.WalletSheet
import app.light.wallet.ui.theme.MonoFont
import app.light.wallet.ui.theme.Tokens
import kotlinx.coroutines.launch

@Composable
fun SettingsTab(
    repository: WalletRepository,
    onOpenSheet: (WalletSheet) -> Unit,
    onWalletWiped: () -> Unit,
) {
    val context = LocalContext.current
    val uiScope = androidx.compose.runtime.rememberCoroutineScope()
    var unit by remember { mutableStateOf(repository.displayUnit) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 18.dp),
    ) {
        Text("Settings", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(top = 6.dp, bottom = 14.dp))

        SectionLabel("Display unit")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            listOf("sat" to "sat", "msat" to "msat", "btc" to "BTC").forEach { (value, label) ->
                val on = unit == value
                Box(
                    modifier = Modifier
                        .weight(1f)
                        .height(42.dp)
                        .background(if (on) Tokens.Accent.copy(alpha = .1f) else Tokens.Card, RoundedCornerShape(12.dp))
                        .border(1.dp, if (on) Tokens.Accent.copy(alpha = .4f) else Tokens.BorderSoft, RoundedCornerShape(12.dp))
                        .noRipple {
                            unit = value
                            repository.displayUnit = value
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        label,
                        style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.sp),
                        color = if (on) Tokens.Accent else Tokens.Dim,
                    )
                }
            }
        }

        SectionLabel("Security", topPadding = 20)
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Tokens.Card, RoundedCornerShape(16.dp))
                .border(1.dp, Tokens.BorderSoft, RoundedCornerShape(16.dp)),
        ) {
            SettingsRow(
                icon = { Icon(Icons.Outlined.Lock, null, tint = Tokens.Accent, modifier = Modifier.size(14.dp)) },
                title = "Reveal recovery phrase",
                subtitle = "Anyone with these words controls your funds",
                chevron = true,
            ) { onOpenSheet(WalletSheet.Seed) }
            Divider()
            SettingsRow(
                icon = { Icon(Icons.Outlined.FileDownload, null, tint = Tokens.Accent, modifier = Modifier.size(14.dp)) },
                title = "Copy client.crt",
                subtitle = "Greenlight certificate · clipboard",
            ) {
                uiScope.launch {
                    repository.loadDeveloperCertPem()
                        ?.let { copyToClipboard(context, "client.crt", it, sensitive = true) }
                }
            }
            Divider()
            SettingsRow(
                icon = { Icon(Icons.Outlined.FileDownload, null, tint = Tokens.Accent, modifier = Modifier.size(14.dp)) },
                title = "Copy client-key.pem",
                subtitle = "Keep this secret",
            ) {
                uiScope.launch {
                    repository.loadDeveloperKeyPem()
                        ?.let { copyToClipboard(context, "client-key.pem", it, sensitive = true) }
                }
            }
            Divider()
            SettingsRow(
                icon = { Icon(Icons.Outlined.OpenInNew, null, tint = Tokens.Accent, modifier = Modifier.size(14.dp)) },
                title = "Source code",
                subtitle = "github.com/olegfomenko/light-app",
                monoSubtitle = true,
            ) {
                context.startActivity(
                    android.content.Intent(
                        android.content.Intent.ACTION_VIEW,
                        android.net.Uri.parse("https://github.com/olegfomenko/light-app"),
                    ),
                )
            }
        }

        SectionLabel("Danger zone", topPadding = 20)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Tokens.Red.copy(alpha = .05f), RoundedCornerShape(16.dp))
                .border(1.dp, Tokens.Red.copy(alpha = .25f), RoundedCornerShape(16.dp))
                .noRipple { onOpenSheet(WalletSheet.DropWallet) }
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Box(
                modifier = Modifier.size(32.dp).background(Tokens.Red.copy(alpha = .1f), RoundedCornerShape(10.dp)),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Outlined.Delete, null, tint = Tokens.Red, modifier = Modifier.size(14.dp)) }
            Column {
                Text("Delete wallet data", style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold), color = Tokens.Red)
                Text("Wipes seed and certificates from this device", style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.5.sp), color = Tokens.Dim)
            }
        }

        Text(
            "LightApp 0.1 · Core Lightning · Greenlight",
            style = MaterialTheme.typography.bodySmall.copy(fontSize = 12.sp, fontFamily = MonoFont),
            color = Tokens.Faint,
            modifier = Modifier.fillMaxWidth().padding(vertical = 24.dp),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
    }
}

@Composable
private fun SectionLabel(text: String, topPadding: Int = 4) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Bold),
        color = Tokens.Label,
        modifier = Modifier.padding(top = topPadding.dp, bottom = 8.dp, start = 2.dp),
    )
}

@Composable
private fun Divider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(Color(0x0AFFFFFF)))
}

@Composable
private fun SettingsRow(
    icon: @Composable () -> Unit,
    title: String,
    subtitle: String,
    chevron: Boolean = false,
    monoSubtitle: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .noRipple(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier.size(32.dp).background(Tokens.Accent.copy(alpha = .08f), RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center,
        ) { icon() }
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium.copy(fontSize = 15.sp, fontWeight = FontWeight.Bold))
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall.copy(
                    fontSize = 12.5.sp,
                    fontFamily = if (monoSubtitle) MonoFont else null,
                ),
                color = Tokens.Dim,
            )
        }
        if (chevron) Icon(Icons.Filled.ChevronRight, null, tint = Tokens.Faint, modifier = Modifier.size(16.dp))
    }
}
