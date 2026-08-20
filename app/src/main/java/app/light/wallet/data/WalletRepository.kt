package app.light.wallet.data

import app.light.wallet.core.CreateInvoiceParams
import app.light.wallet.core.CreateInvoiceResult
import app.light.wallet.core.LightNode
import app.light.wallet.core.NodeInfo
import app.light.wallet.core.Funds
import app.light.wallet.core.InvoiceEntry
import app.light.wallet.core.ListInvoicesParams
import app.light.wallet.core.ListPaysParams
import app.light.wallet.core.PayListEntry
import app.light.wallet.core.PayParams
import app.light.wallet.core.PeerChannel
import app.light.wallet.core.WalletTx
import app.light.wallet.core.RenepayParams
import app.light.wallet.core.XpayParams
import app.light.wallet.core.connectNode
import app.light.wallet.core.recoverNode
import app.light.wallet.core.registerNode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong

sealed interface ConnState {
    data object Idle : ConnState
    data object Connecting : ConnState
    data class Connected(val info: NodeInfo?) : ConnState
    data class Failed(val message: String) : ConnState
}

enum class PayMethod { PAY, XPAY, RENEPAY }

sealed interface PayCommand {
    val invstring: String

    data class Pay(val params: PayParams) : PayCommand {
        override val invstring get() = params.bolt11
    }

    data class Xpay(val params: XpayParams) : PayCommand {
        override val invstring get() = params.invstring
    }

    data class Rene(val params: RenepayParams) : PayCommand {
        override val invstring get() = params.invstring
    }

    val method: PayMethod
        get() = when (this) {
            is Pay -> PayMethod.PAY
            is Xpay -> PayMethod.XPAY
            is Rene -> PayMethod.RENEPAY
        }
}

enum class ActivePaymentStatus { PAYING, PENDING, COMPLETE, FAILED }

/** An in-app record of a payment started from this session. */
data class ActivePayment(
    val id: Long,
    val invstring: String,
    val description: String? = null,
    val method: PayMethod,
    val status: ActivePaymentStatus,
    val startedAt: Long,
    val amountMsat: ULong? = null,
    val feeMsat: ULong? = null,
    val preimage: String? = null,
    val error: String? = null,
)

/**
 * Owns the connection to the Greenlight node and all app-level state.
 * Payments run in the application scope, so the UI stays fully usable
 * while a payment is in flight.
 */
class WalletRepository(
    private val storage: SecureStorage,
    private val scope: CoroutineScope,
) {
    private val _connState = MutableStateFlow<ConnState>(ConnState.Idle)
    val connState: StateFlow<ConnState> = _connState.asStateFlow()

    private val _activePayments = MutableStateFlow<List<ActivePayment>>(emptyList())
    val activePayments: StateFlow<List<ActivePayment>> = _activePayments.asStateFlow()

    // ------------------------------------------------------------------
    // Shared node data: each RPC has exactly one flow; every screen reads
    // from these, so one refresh updates every screen that shows the data.
    // ------------------------------------------------------------------

    val funds = MutableStateFlow<Funds?>(null)
    val invoices = MutableStateFlow<List<InvoiceEntry>?>(null)
    val pays = MutableStateFlow<List<PayListEntry>?>(null)
    val transactions = MutableStateFlow<List<WalletTx>?>(null)
    val channels = MutableStateFlow<List<PeerChannel>?>(null)

    // One in-flight fetch per data kind, conflated to the latest request: a
    // refresh fired right after an action (pay, create invoice) cancels the
    // older job and runs fresh, so it can't reuse data read before the action.
    private val fetchJobs = HashMap<String, kotlinx.coroutines.Job>()

    private fun fetch(key: String, block: suspend () -> Unit): kotlinx.coroutines.Job =
        synchronized(fetchJobs) {
            fetchJobs.remove(key)?.cancel()
            val job = scope.launch {
                try {
                    block()
                } catch (c: CancellationException) {
                    throw c
                } catch (e: Exception) {
                    android.util.Log.w("LightApp", "refresh '$key' failed: ${e.message}")
                }
            }
            fetchJobs[key] = job
            job
        }

    fun refreshFunds() = fetch("funds") { node?.let { funds.value = it.listFunds() } }

    fun refreshInvoices() = fetch("invoices") {
        node?.let {
            invoices.value = it.listInvoices(ListInvoicesParams(null, null, null, null, null, null))
        }
    }

    fun refreshPays() = fetch("pays") {
        node?.let {
            pays.value = it.listPays(ListPaysParams(null, null, null, null, null, null))
        }
    }

    fun refreshTransactions() = fetch("transactions") {
        node?.let { transactions.value = it.listTransactions() }
    }

    fun refreshChannels() = fetch("channels") { node?.let { channels.value = it.listChannels() } }

    /** Refresh getinfo so the current block height (used for tx ages/confs) advances. */
    fun refreshInfo() = fetch("info") {
        node?.let { n ->
            runCatching { n.getInfo() }.getOrNull()?.let { info ->
                if (node != null) _connState.value = ConnState.Connected(info)
            }
        }
    }

    /** What the Main screen shows (and its 30s auto-refresh fetches). */
    fun refreshMain() {
        refreshInfo(); refreshFunds(); refreshInvoices(); refreshPays(); refreshTransactions()
    }

    fun refreshAll() {
        refreshMain(); refreshChannels()
    }

    @Volatile
    var node: LightNode? = null
        private set

    // Set while the whole app is in the background; used to shut the node
    // (and its signer stream) down instead of burning battery invisibly.
    @Volatile
    private var inBackground = false

    // Non-secret settings migration (touches the Keystore, so off-main).
    // connect() awaits it so the first post-update connect can't read a
    // pre-migration default network.
    private val migration: kotlinx.coroutines.Job =
        scope.launch { runCatching { storage.migrateNonSecrets() } }

    private val connectMutex = Mutex()
    private val paymentIds = AtomicLong(1)

    // >0 while a payment is being dispatched; blocks the background node release
    // so the signer can't be shut down out from under an in-flight HTLC.
    private val inFlightPayments = AtomicInteger(0)

    fun hasWallet(): Boolean = storage.hasWallet()

    // ------------------------------------------------------------------
    // App lifecycle: connect while visible, release when backgrounded
    // ------------------------------------------------------------------

    fun onAppForeground() {
        inBackground = false
        if (hasWallet()) connectInBackground()
    }

    fun onAppBackground() {
        inBackground = true
        releaseIfIdle()
    }

    /**
     * Drop the node handle (which also stops the in-process signer) when the
     * app is backgrounded and nothing is being paid. Keeping the signer's
     * streaming RPC alive in the background is the single largest
     * battery/CPU cost of this app; the node is re-scheduled in a couple of
     * seconds on the next foreground anyway.
     */
    private fun releaseIfIdle() {
        scope.launch {
            connectMutex.withLock {
                if (!inBackground) return@launch
                // Only an in-progress dispatch (an RPC we are mid-call on) must
                // keep the signer alive. A "pending" HTLC persists on the node
                // and resumes on the next reconnect, so it must not block release.
                if (inFlightPayments.get() > 0) {
                    return@launch // finish the in-flight call first
                }
                val n = node ?: return@launch
                node = null
                _connState.value = ConnState.Idle
                runCatching { n.close() }
            }
        }
    }

    val network: String get() = storage.network

    // ------------------------------------------------------------------
    // Onboarding
    // ------------------------------------------------------------------

    /**
     * Register (or recover, when [restore] is true) the Greenlight node and
     * persist everything the app needs to reconnect later.
     */
    suspend fun setupWallet(
        mnemonic: String,
        passphrase: String,
        network: String,
        developerCert: ByteArray,
        developerKey: ByteArray,
        restore: Boolean,
    ) {
        val creds = if (restore) {
            recoverNode(mnemonic, passphrase, network, developerCert, developerKey)
        } else {
            registerNode(mnemonic, passphrase, network, developerCert, developerKey)
        }
        // Keystore writes (and, on a fresh install, the StrongBox keygen the
        // first write triggers) must not run on the caller's Main dispatcher.
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            storage.mnemonic = mnemonic
            storage.passphrase = passphrase
            storage.network = network
            storage.deviceCreds = creds
            // Kept for Settings -> export; uploaded once at onboarding.
            storage.developerCert = developerCert
            storage.developerKey = developerKey
        }
    }

    /** StrongBox decrypt — never call from the main thread/composition. */
    suspend fun loadMnemonicWords(): List<String> =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            storage.mnemonic?.trim()?.split(" ").orEmpty()
        }

    suspend fun loadDeveloperCertPem(): String? =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            storage.developerCert?.decodeToString()
        }

    suspend fun loadDeveloperKeyPem(): String? =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            storage.developerKey?.decodeToString()
        }

    var displayUnit: String
        get() = storage.displayUnit
        set(v) { storage.displayUnit = v }

    /** Danger zone: wipe seed + creds and stop the node. */
    fun wipeWallet() {
        scope.launch {
            connectMutex.withLock {
                node?.let { runCatching { it.close() } }
                node = null
                _connState.value = ConnState.Idle
                storage.wipe()
            }
        }
    }

    // ------------------------------------------------------------------
    // Connection ("run the scheduler each time the user enters the app")
    // ------------------------------------------------------------------

    fun connectInBackground(force: Boolean = false) {
        scope.launch { connect(force) }
    }

    suspend fun connect(force: Boolean = false) {
        migration.join()
        connectMutex.withLock {
            if (!force && (node != null || _connState.value is ConnState.Connecting)) return
            val mnemonic = storage.mnemonic ?: run {
                _connState.value = ConnState.Failed("wallet not set up")
                return
            }
            val creds = storage.deviceCreds ?: run {
                _connState.value = ConnState.Failed("device credentials missing")
                return
            }
            _connState.value = ConnState.Connecting
            try {
                // A forced reconnect must stop the previous signer first —
                // otherwise it keeps running until the GC finalizes the old
                // node handle and we end up with two live signer streams.
                node?.let { runCatching { it.close() } }
                node = null
                val n = connectNode(mnemonic, storage.passphrase, storage.network, creds)
                node = n
                val info = runCatching { n.getInfo() }.getOrNull()
                _connState.value = ConnState.Connected(info)
                refreshAll()
            } catch (e: Exception) {
                node = null
                _connState.value = ConnState.Failed(e.message ?: "connection failed")
            }
        }
    }

    fun requireNode(): LightNode =
        node ?: throw IllegalStateException("node is not connected yet")

    // ------------------------------------------------------------------
    // Asynchronous payments
    // ------------------------------------------------------------------

    /**
     * Fire a payment without blocking the caller. Track progress through
     * [activePayments]; the final state also shows up in listpays.
     */
    fun startPayment(command: PayCommand, description: String? = null): Long {
        val id = paymentIds.getAndIncrement()
        val record = ActivePayment(
            id = id,
            invstring = command.invstring,
            description = description?.ifBlank { null },
            method = command.method,
            status = ActivePaymentStatus.PAYING,
            startedAt = System.currentTimeMillis(),
        )
        inFlightPayments.incrementAndGet()
        _activePayments.update { listOf(record) + it }

        scope.launch {
            try {
                val update = try {
                    val n = requireNode()
                    when (command) {
                        is PayCommand.Pay -> {
                            val r = n.pay(command.params)
                            record.copy(
                                status = payStatus(r.status),
                                amountMsat = r.amountMsat,
                                feeMsat = feeOf(r.amountSentMsat, r.amountMsat),
                                preimage = r.paymentPreimage.ifBlank { null },
                            )
                        }

                        is PayCommand.Xpay -> {
                            val r = n.xpay(command.params)
                            // xpay raises on failure; treat an empty preimage as
                            // failed rather than silently reporting success.
                            record.copy(
                                status = if (r.paymentPreimage.isNotBlank())
                                    ActivePaymentStatus.COMPLETE else ActivePaymentStatus.FAILED,
                                amountMsat = r.amountMsat,
                                feeMsat = feeOf(r.amountSentMsat, r.amountMsat),
                                preimage = r.paymentPreimage.ifBlank { null },
                            )
                        }

                        is PayCommand.Rene -> {
                            val r = n.renePay(command.params)
                            record.copy(
                                status = payStatus(r.status),
                                amountMsat = r.amountMsat,
                                feeMsat = feeOf(r.amountSentMsat, r.amountMsat),
                                preimage = r.paymentPreimage.ifBlank { null },
                            )
                        }
                    }
                } catch (e: Exception) {
                    // The HTLC may still settle server-side; never imply it is
                    // safe to blindly retry (that is how you double-pay).
                    record.copy(
                        status = ActivePaymentStatus.FAILED,
                        error = (e.message ?: "payment failed") +
                            " — check Activity before retrying; it may still be in flight.",
                    )
                }
                _activePayments.update { list ->
                    list.map { if (it.id == update.id) update else it }
                }
                // A finished payment changes balances and the pays list.
                refreshFunds(); refreshPays()
            } finally {
                inFlightPayments.decrementAndGet()
                // If the app was backgrounded during the payment, the node was
                // kept alive; release it now that nothing is in flight.
                if (inBackground) releaseIfIdle()
            }
        }
        return id
    }

    // A CLN pay/renepay result: "pending" means the HTLC is still in flight,
    // NOT failed — declaring it FAILED invites a double payment.
    private fun payStatus(status: String): ActivePaymentStatus = when (status) {
        "complete" -> ActivePaymentStatus.COMPLETE
        "failed" -> ActivePaymentStatus.FAILED
        else -> ActivePaymentStatus.PENDING // still in flight; NOT failed
    }

    // Unsigned subtraction wraps on underflow; a sent amount below the invoice
    // amount (failed/pending dispatch) must not render as ~1.8e19 msat.
    private fun feeOf(sentMsat: ULong, amountMsat: ULong): ULong? =
        if (sentMsat >= amountMsat) sentMsat - amountMsat else null

    suspend fun createInvoice(params: CreateInvoiceParams): CreateInvoiceResult =
        requireNode().createInvoice(params).also { refreshInvoices() }
}
