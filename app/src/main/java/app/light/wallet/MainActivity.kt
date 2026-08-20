package app.light.wallet

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import app.light.wallet.ui.AppRoot
import app.light.wallet.ui.theme.LightAppTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as LightApplication
        setContent {
            LightAppTheme {
                AppRoot(repository = app.repository)
            }
        }
    }

    // Note: connecting/releasing the node is handled app-wide by the
    // ProcessLifecycleOwner observer in LightApplication.
}
