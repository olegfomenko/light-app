package app.light.wallet

import android.app.Application
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import app.light.wallet.data.SecureStorage
import app.light.wallet.data.WalletRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class LightApplication : Application() {

    // Application-scoped coroutine scope: payments keep running while the user
    // navigates around (and even if every Activity is destroyed).
    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    lateinit var storage: SecureStorage
        private set
    lateinit var repository: WalletRepository
        private set

    override fun onCreate() {
        super.onCreate()
        // Send Rust-side logs (signer connection state, errors) to logcat
        // under the tag "lightcore".
        app.light.wallet.core.initLogging(BuildConfig.DEBUG)
        storage = SecureStorage(this)
        repository = WalletRepository(storage, appScope)

        // Connect while the app is visible, release the node + signer when it
        // goes to the background (unless a payment is still in flight) —
        // keeping the signer's streaming RPC alive invisibly is the largest
        // battery/CPU cost of the app.
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) = repository.onAppForeground()
            override fun onStop(owner: LifecycleOwner) = repository.onAppBackground()
        })
    }
}
