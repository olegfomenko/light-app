import Foundation
import Observation
import UIKit
import os

/// Mirrors Android's `android.util.Log.w("LightApp", ...)` channel.
private let walletLog = Logger(subsystem: "app.light.wallet", category: "WalletRepository")

// ---------------------------------------------------------------------------
// Connection state
// ---------------------------------------------------------------------------

/// Connection lifecycle of the Greenlight node (Kotlin: `sealed interface
/// ConnState` with Idle / Connecting / Connected / Failed).
enum ConnState: Equatable {
    case idle
    case connecting
    case connected(NodeInfo?)
    case error(String)

    /// The node info when connected (nil while getinfo hasn't answered yet,
    /// or in any other state). Convenience for views that only need the info.
    var info: NodeInfo? {
        if case .connected(let info) = self { return info }
        return nil
    }
}

// ---------------------------------------------------------------------------
// Payments
// ---------------------------------------------------------------------------

enum PayMethod: Equatable, Hashable {
    case PAY, XPAY, RENEPAY
}

/// Which CLN payment RPC to run and with what parameters (Kotlin: `sealed
/// interface PayCommand`). The params types come straight from the generated
/// core bindings.
enum PayCommand {
    case pay(PayParams)
    case xpay(XpayParams)
    case rene(RenepayParams)

    /// The invoice being paid, whatever the method.
    var invstring: String {
        switch self {
        case .pay(let p): return p.bolt11
        case .xpay(let p): return p.invstring
        case .rene(let p): return p.invstring
        }
    }

    var method: PayMethod {
        switch self {
        case .pay: return .PAY
        case .xpay: return .XPAY
        case .rene: return .RENEPAY
        }
    }
}

enum ActivePaymentStatus: Equatable, Hashable {
    case PAYING, PENDING, COMPLETE, FAILED
}

/// An in-app record of a payment started from this session.
struct ActivePayment: Identifiable, Equatable {
    let id: Int64
    let invstring: String
    var description: String? = nil
    let method: PayMethod
    var status: ActivePaymentStatus
    /// Milliseconds since epoch (Kotlin: `System.currentTimeMillis()`).
    let startedAt: Int64
    var amountMsat: UInt64? = nil
    var feeMsat: UInt64? = nil
    var preimage: String? = nil
    var error: String? = nil
}

/// Thrown by `requireNode()` (Kotlin: `IllegalStateException`).
struct NodeNotConnectedError: LocalizedError {
    var errorDescription: String? { "node is not connected yet" }
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// The data kinds the repository fetches from the node — one single-flight
/// slot per kind (Kotlin used string keys into a job map).
enum FetchKind: String, Hashable, CaseIterable {
    case info, funds, invoices, pays, transactions, channels
}

/// Owns the connection to the Greenlight node and all app-level state.
/// Payments run as free-standing tasks, so the UI stays fully usable while a
/// payment is in flight.
///
/// `@MainActor`: every piece of state is read by SwiftUI during view updates,
/// so all mutations happen on the main actor — this is the iOS analogue of
/// the Kotlin `StateFlow`s being safely collectable from composition. The
/// actual RPC work still suspends off the main thread (the Rust core drives
/// its own executor); only the state writes hop back here.
@MainActor
@Observable
final class WalletRepository {

    // ------------------------------------------------------------------
    // Observable state
    // ------------------------------------------------------------------

    private(set) var connState: ConnState = .idle

    private(set) var activePayments: [ActivePayment] = []

    // Shared node data: each RPC has exactly one property; every screen reads
    // from these, so one refresh updates every screen that shows the data.
    // `nil` = never fetched (the Kotlin flows start at null the same way).
    private(set) var funds: Funds? = nil
    private(set) var invoices: [InvoiceEntry]? = nil
    private(set) var pays: [PayListEntry]? = nil
    private(set) var transactions: [WalletTx]? = nil
    private(set) var channels: [PeerChannel]? = nil

    /// The live node handle. There is no explicit `close()` in the Swift
    /// bindings: dropping the last reference deinitializes the Rust object,
    /// which shuts the signer down — so "close the node" is spelled
    /// `node = nil` throughout this file. In-flight RPCs hold their own
    /// cloned pointer, so releasing our reference never crashes a call that
    /// is still running.
    private(set) var node: LightNode? = nil

    /// "sat" | "msat" | "btc". Stored (not computed) so `@Observable` tracks
    /// it and every amount on screen re-renders when the user flips the unit;
    /// `didSet` writes it through to the plain preference.
    var displayUnit: String {
        didSet { storage.displayUnit = displayUnit }
    }

    /// Greenlight network name (plain preference; changes only via
    /// `setupWallet`, so a computed passthrough is enough).
    var network: String { storage.network }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    @ObservationIgnored private let storage: SecureStorage

    // Set while the whole app is in the background; used to shut the node
    // (and its signer stream) down instead of burning battery invisibly.
    @ObservationIgnored private var inBackground = false

    /// One in-flight fetch task per data kind. A second trigger while one is
    /// running joins the running task and returns — it never stacks a second
    /// RPC of the same kind. (Kotlin cancelled-and-restarted instead; that
    /// buys nothing here because Swift task cancellation does not abort the
    /// underlying Rust future — the RPC would run to completion anyway. Any
    /// staleness from joining a fetch that raced an action is corrected by
    /// the action's own refresh hooks and the 30 s auto-refresh.)
    @ObservationIgnored private var fetchTasks: [FetchKind: Task<Void, Never>] = [:]
    @ObservationIgnored private var fetchGen: [FetchKind: Int] = [:]

    /// Serializes connect / release / wipe — the iOS analogue of the Kotlin
    /// `connectMutex`. Each entrant chains behind the previous task, so
    /// concurrent `connect()` calls cannot double-create nodes (two live
    /// signer streams for one wallet), and a release cannot interleave with a
    /// connect halfway through.
    @ObservationIgnored private var connectChain: Task<Void, Never>? = nil

    /// Monotonic id source for `ActivePayment` (Kotlin: `AtomicLong(1)`;
    /// plain Int64 here because everything runs on the main actor).
    @ObservationIgnored private var nextPaymentId: Int64 = 1

    /// > 0 while a payment is being dispatched; blocks the background node
    /// release so the signer can't be shut down out from under an in-flight
    /// HTLC (Kotlin: `AtomicInteger`; main-actor serialization makes a plain
    /// Int race-free).
    @ObservationIgnored private var inFlightPayments = 0

    /// iOS-only: while `inFlightPayments > 0` we hold a background task
    /// assertion so the OS gives the in-flight RPC time to finish if the user
    /// backgrounds the app mid-payment.
    @ObservationIgnored private var bgTask: UIBackgroundTaskIdentifier = .invalid

    /// The 30 s Main-screen refresh loop; driven by the Main tab's
    /// appear/disappear.
    @ObservationIgnored private var autoRefreshTask: Task<Void, Never>? = nil

    init(storage: SecureStorage = SecureStorage()) {
        self.storage = storage
        self.displayUnit = storage.displayUnit
    }

    // Note: Android ran a non-secret settings migration here that connect()
    // had to await. iOS starts fresh (non-secrets are already plain
    // UserDefaults), so there is nothing to migrate and nothing to join.

    func hasWallet() -> Bool { storage.hasWallet() }

    // ------------------------------------------------------------------
    // Single-flight fetch machinery
    // ------------------------------------------------------------------

    @discardableResult
    private func fetch(
        _ kind: FetchKind,
        force: Bool = false,
        _ block: @escaping @MainActor () async throws -> Void
    ) -> Task<Void, Never> {
        if let running = fetchTasks[kind] {
            // Passive refreshes join the in-flight fetch. Action hooks (a
            // payment just finished, a channel just opened) must NOT: that
            // fetch was dispatched BEFORE the action and would persist
            // pre-action data — e.g. a completed payment missing from
            // Activity, which reads as "failed" and invites a double-pay.
            // Force = wait for the stale fetch, then fetch again fresh.
            guard force else { return running }
            let task = Task { @MainActor in
                await running.value
                await self.fetch(kind, block).value
            }
            return task
        }
        fetchGen[kind, default: 0] += 1
        let gen = fetchGen[kind]!
        let task = Task { @MainActor in
            do {
                try await block()
            } catch is CancellationError {
                // cancelled fetches (wipe) end silently
            } catch {
                walletLog.warning("refresh '\(kind.rawValue, privacy: .public)' failed: \(Self.errorMessage(error, fallback: "unknown"), privacy: .public)")
            }
            // FIX (single-flight after wipe): only clear our own registration —
            // a cancelled task's tail must not evict a successor fetch.
            // Clear only OUR registration: a cancelled task's tail running
            // late must not evict a successor fetch (single-flight after wipe).
            if self.fetchGen[kind] == gen {
                self.fetchTasks[kind] = nil
            }
        }
        fetchTasks[kind] = task
        return task
    }

    // Each refresh re-checks `Task.isCancelled` after the RPC returns so a
    // fetch cancelled by `wipe()` can never re-populate state post-wipe
    // (Kotlin got the same guarantee from coroutine-job cancellation).

    @discardableResult
    func refreshFunds(force: Bool = false) -> Task<Void, Never> {
        fetch(.funds, force: force) {
            guard let n = self.node else { return }
            let v = try await n.listFunds()
            guard !Task.isCancelled else { return }
            self.funds = v
        }
    }

    @discardableResult
    func refreshInvoices(force: Bool = false) -> Task<Void, Never> {
        fetch(.invoices, force: force) {
            guard let n = self.node else { return }
            let v = try await n.listInvoices(params: ListInvoicesParams(
                label: nil, invstring: nil, paymentHashHex: nil, index: nil, start: nil, limit: nil
            ))
            guard !Task.isCancelled else { return }
            self.invoices = v
        }
    }

    @discardableResult
    func refreshPays(force: Bool = false) -> Task<Void, Never> {
        fetch(.pays, force: force) {
            guard let n = self.node else { return }
            let v = try await n.listPays(params: ListPaysParams(
                bolt11: nil, paymentHashHex: nil, status: nil, index: nil, start: nil, limit: nil
            ))
            guard !Task.isCancelled else { return }
            self.pays = v
        }
    }

    @discardableResult
    func refreshTransactions() -> Task<Void, Never> {
        fetch(.transactions) {
            guard let n = self.node else { return }
            let v = try await n.listTransactions()
            guard !Task.isCancelled else { return }
            self.transactions = v
        }
    }

    @discardableResult
    func refreshChannels(force: Bool = false) -> Task<Void, Never> {
        fetch(.channels, force: force) {
            guard let n = self.node else { return }
            let v = try await n.listChannels()
            guard !Task.isCancelled else { return }
            self.channels = v
        }
    }

    /// Refresh getinfo so the current block height (used for tx ages/confs)
    /// advances.
    @discardableResult
    func refreshInfo() -> Task<Void, Never> {
        fetch(.info) {
            guard let n = self.node else { return }
            guard let info = try? await n.getInfo() else { return }
            guard !Task.isCancelled, self.node != nil else { return }
            self.connState = .connected(info)
        }
    }

    /// What the Main screen shows (and its 30 s auto-refresh fetches).
    func refreshMain() {
        refreshInfo(); refreshFunds(); refreshInvoices(); refreshPays(); refreshTransactions()
    }

    func refreshAll() {
        refreshMain(); refreshChannels()
    }

    /// Fetch a data kind only if it has never been fetched (tab entry: show
    /// what we have, fetch only on first visit; pull-to-refresh calls the
    /// unconditional variants).
    func fetchIfNeeded(_ kind: FetchKind) {
        switch kind {
        case .funds: if funds == nil { refreshFunds() }
        case .invoices: if invoices == nil { refreshInvoices() }
        case .pays: if pays == nil { refreshPays() }
        case .transactions: if transactions == nil { refreshTransactions() }
        case .channels: if channels == nil { refreshChannels() }
        case .info: if case .connected(nil) = connState { refreshInfo() }
        }
    }

    /// Action hook: after a channel open or close both the channel list and
    /// the on-chain/channel balances are stale.
    func refreshAfterChannelAction() {
        refreshChannels(force: true); refreshFunds(force: true)
    }

    // ------------------------------------------------------------------
    // App lifecycle: connect while visible, release when backgrounded
    // ------------------------------------------------------------------

    func onAppForeground() {
        inBackground = false
        if hasWallet() { connectInBackground() }
    }

    func onAppBackground() {
        inBackground = true
        releaseIfIdle()
    }

    /// Drop the node handle (which also stops the in-process signer) when the
    /// app is backgrounded and nothing is being paid. Keeping the signer's
    /// streaming RPC alive in the background is the single largest
    /// battery/CPU cost of this app; the node is re-scheduled in a couple of
    /// seconds on the next foreground anyway.
    private func releaseIfIdle() {
        serialized {
            guard self.inBackground else { return }
            // Only an in-progress dispatch (an RPC we are mid-call on) must
            // keep the signer alive. A "pending" HTLC persists on the node
            // and resumes on the next reconnect, so it must not block release.
            guard self.inFlightPayments == 0 else { return } // finish the in-flight call first
            guard self.node != nil else { return }
            self.node = nil // deinit frees the Rust node and stops the signer
            self.connState = .idle
        }
    }

    // ------------------------------------------------------------------
    // Onboarding
    // ------------------------------------------------------------------

    /// Register (or recover, when `restore` is true) the Greenlight node,
    /// persist everything the app needs to reconnect later, then connect.
    func setupWallet(
        mnemonic: String,
        passphrase: String,
        network: String,
        developerCert: Data,
        developerKey: Data,
        restore: Bool
    ) async throws {
        let creds: Data
        if restore {
            creds = try await recoverNode(
                mnemonic: mnemonic, passphrase: passphrase, network: network,
                developerCert: developerCert, developerKey: developerKey
            )
        } else {
            creds = try await registerNode(
                mnemonic: mnemonic, passphrase: passphrase, network: network,
                developerCert: developerCert, developerKey: developerKey
            )
        }
        // Keychain writes must not run on the main actor (the Android rule —
        // never do secret-store work on the UI path — carries over even
        // though the Keychain is much cheaper than StrongBox).
        let storage = self.storage
        let persisted = await Task.detached { () -> Bool in
            // The seed and device credentials are the two items whose loss is
            // unrecoverable — write-and-verify them; everything else can be
            // re-uploaded or defaulted.
            guard storage.putBytesVerified(SecureStorage.kMnemonic, Data(mnemonic.utf8)),
                  storage.putBytesVerified(SecureStorage.kDeviceCreds, creds)
            else { return false }
            storage.passphrase = passphrase
            storage.network = network
            // Kept for Settings -> export; uploaded once at onboarding.
            storage.developerCert = developerCert
            storage.developerKey = developerKey
            return true
        }.value
        guard persisted else {
            throw CoreError.Msg(message:
                "Could not store the wallet securely on this device — the seed was NOT saved. " +
                "Nothing was lost (your node is registered), but do not fund this wallet until " +
                "setup succeeds. Free up Keychain space or restart, then try Recover.")
        }
        await connect()
    }

    /// Secret decrypt — kept off the main actor (Kotlin: Dispatchers.Default).
    func loadMnemonicWords() async -> [String] {
        let storage = self.storage
        return await Task.detached {
            (storage.mnemonic ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: " ")
                .map(String.init)
        }.value
    }

    func loadDeveloperCertPem() async -> String? {
        let storage = self.storage
        return await Task.detached {
            storage.developerCert.flatMap { String(data: $0, encoding: .utf8) }
        }.value
    }

    func loadDeveloperKeyPem() async -> String? {
        let storage = self.storage
        return await Task.detached {
            storage.developerKey.flatMap { String(data: $0, encoding: .utf8) }
        }.value
    }

    /// Danger zone: wipe seed + creds, stop the node and reset all state.
    func wipe() {
        serialized {
            // Straggler fetches must not re-populate state after the reset.
            self.fetchTasks.values.forEach { $0.cancel() }
            self.fetchTasks.removeAll()
            self.node = nil
            self.connState = .idle
            let storage = self.storage
            await Task.detached { storage.wipe() }.value
            self.funds = nil
            self.invoices = nil
            self.pays = nil
            self.transactions = nil
            self.channels = nil
            self.activePayments = []
            // Re-persists the default; behaviorally identical to fresh install.
            self.displayUnit = "sat"
        }
    }

    // ------------------------------------------------------------------
    // Connection ("run the scheduler each time the user enters the app")
    // ------------------------------------------------------------------

    func connectInBackground(force: Bool = false) {
        let _ = serializedConnect(force: force)
    }

    func connect(force: Bool = false) async {
        await serializedConnect(force: force).value
    }

    private func serializedConnect(force: Bool) -> Task<Void, Never> {
        serialized { await self.doConnect(force: force) }
    }

    /// Runs strictly inside the connect chain — see `serialized`.
    private func doConnect(force: Bool) async {
        if !force {
            if node != nil { return }
            if case .connecting = connState { return }
        }
        // Keychain reads happen off the main actor; one hop grabs everything.
        let storage = self.storage
        let (mnemonic, creds, passphrase, network) = await Task.detached {
            (storage.mnemonic, storage.deviceCreds, storage.passphrase, storage.network)
        }.value
        guard let mnemonic else {
            connState = .error("wallet not set up")
            return
        }
        guard let creds else {
            connState = .error("device credentials missing")
            return
        }
        connState = .connecting
        do {
            // A forced reconnect must stop the previous signer first —
            // dropping the handle frees the Rust node; otherwise we would end
            // up with two live signer streams.
            node = nil
            let n = try await connectNode(
                mnemonic: mnemonic, passphrase: passphrase, network: network, deviceCreds: creds
            )
            node = n
            let info = try? await n.getInfo()
            connState = .connected(info)
            refreshAll()
        } catch {
            node = nil
            connState = .error(Self.errorMessage(error, fallback: "connection failed"))
        }
    }

    /// The async-mutex primitive: every critical section chains behind the
    /// previous one, so connect / release / wipe never interleave.
    @discardableResult
    private func serialized(_ body: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = connectChain
        let next = Task { @MainActor in
            await previous?.value
            await body()
        }
        connectChain = next
        return next
    }

    func requireNode() throws -> LightNode {
        guard let n = node else { throw NodeNotConnectedError() }
        return n
    }

    // ------------------------------------------------------------------
    // Asynchronous payments
    // ------------------------------------------------------------------

    /// Fire a payment without blocking the caller. Track progress through
    /// `activePayments`; the final state also shows up in listpays.
    @discardableResult
    func startPayment(command: PayCommand, description: String? = nil) -> Int64 {
        let id = nextPaymentId
        nextPaymentId += 1
        let record = ActivePayment(
            id: id,
            invstring: command.invstring,
            description: description.flatMap(Self.blankToNil),
            method: command.method,
            status: .PAYING,
            startedAt: Int64(Date().timeIntervalSince1970 * 1000)
        )
        // Incremented BEFORE the dispatch task starts so a background release
        // racing this call can never observe "idle" between the UI action and
        // the RPC going out.
        inFlightPayments += 1
        if inFlightPayments == 1 { beginBackgroundHold() }
        activePayments.insert(record, at: 0)

        Task { @MainActor in
            defer {
                self.inFlightPayments -= 1
                if self.inFlightPayments == 0 { self.endBackgroundHold() }
                // If the app was backgrounded during the payment, the node was
                // kept alive; release it now that nothing is in flight.
                if self.inBackground { self.releaseIfIdle() }
            }
            var update = record
            do {
                let n = try self.requireNode()
                switch command {
                case .pay(let params):
                    let r = try await n.pay(params: params)
                    update.status = Self.payStatus(r.status)
                    update.amountMsat = r.amountMsat
                    update.feeMsat = Self.feeOf(sentMsat: r.amountSentMsat, amountMsat: r.amountMsat)
                    update.preimage = Self.blankToNil(r.paymentPreimage)

                case .xpay(let params):
                    let r = try await n.xpay(params: params)
                    // xpay raises on failure; treat an empty preimage as
                    // failed rather than silently reporting success.
                    update.status = Self.blankToNil(r.paymentPreimage) != nil ? .COMPLETE : .FAILED
                    update.amountMsat = r.amountMsat
                    update.feeMsat = Self.feeOf(sentMsat: r.amountSentMsat, amountMsat: r.amountMsat)
                    update.preimage = Self.blankToNil(r.paymentPreimage)

                case .rene(let params):
                    let r = try await n.renePay(params: params)
                    update.status = Self.payStatus(r.status)
                    update.amountMsat = r.amountMsat
                    update.feeMsat = Self.feeOf(sentMsat: r.amountSentMsat, amountMsat: r.amountMsat)
                    update.preimage = Self.blankToNil(r.paymentPreimage)
                }
            } catch {
                // The HTLC may still settle server-side; never imply it is
                // safe to blindly retry (that is how you double-pay).
                update = record
                update.status = .FAILED
                update.error = Self.errorMessage(error, fallback: "payment failed")
                    + " — check Activity before retrying; it may still be in flight."
            }
            self.activePayments = self.activePayments.map { $0.id == update.id ? update : $0 }
            // A finished payment changes balances and the pays list.
            self.refreshFunds(force: true)
            self.refreshPays(force: true)
        }
        return id
    }

    /// A CLN pay/renepay result: "pending" means the HTLC is still in flight,
    /// NOT failed — declaring it FAILED invites a double payment.
    private nonisolated static func payStatus(_ status: String) -> ActivePaymentStatus {
        switch status {
        case "complete": return .COMPLETE
        case "failed": return .FAILED
        default: return .PENDING // still in flight; NOT failed
        }
    }

    /// Unsigned subtraction traps on underflow in Swift; a sent amount below
    /// the invoice amount (failed/pending dispatch) must not crash — nor
    /// render as ~1.8e19 msat, as the Kotlin wrap-around would have.
    private nonisolated static func feeOf(sentMsat: UInt64, amountMsat: UInt64) -> UInt64? {
        sentMsat >= amountMsat ? sentMsat - amountMsat : nil
    }

    /// Kotlin `String.ifBlank { null }`.
    private nonisolated static func blankToNil(_ s: String) -> String? {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s
    }

    /// Kotlin `e.message ?: fallback` — the core surfaces every failure as
    /// `CoreError.Msg`, whose generated `localizedDescription` is the ugly
    /// reflection dump, so unwrap the message ourselves.
    private nonisolated static func errorMessage(_ error: Error, fallback: String) -> String {
        if case CoreError.Msg(let message) = error, !message.isEmpty { return message }
        let d = (error as NSError).localizedDescription
        return d.isEmpty ? fallback : d
    }

    // ------------------------------------------------------------------
    // Invoices
    // ------------------------------------------------------------------

    /// Run a one-shot mutating RPC (withdraw, fundchannel, close) under the
    /// same protection a payment gets: the in-flight counter blocks node
    /// release on background, and a UIKit background task keeps the dispatch
    /// alive if the user swipes away mid-broadcast. Without this, a send
    /// interrupted by backgrounding can broadcast on the node while the app
    /// shows an error — which reads as "failed" and invites a double-spend.
    func performGuardedRPC<T: Sendable>(_ op: @MainActor () async throws -> T) async throws -> T {
        inFlightPayments += 1
        if inFlightPayments == 1 { beginBackgroundHold() }
        defer {
            inFlightPayments -= 1
            if inFlightPayments == 0 {
                endBackgroundHold()
                if inBackground { releaseIfIdle() }
            }
        }
        return try await op()
    }

    func createInvoice(params: CreateInvoiceParams) async throws -> CreateInvoiceResult {
        let result = try await requireNode().createInvoice(params: params)
        refreshInvoices(force: true)
        return result
    }

    // ------------------------------------------------------------------
    // 30 s Main auto-refresh (driven by the Main tab on appear/disappear)
    // ------------------------------------------------------------------

    func startMainAutoRefresh() {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                self.refreshMain()
            }
        }
    }

    func stopMainAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    // ------------------------------------------------------------------
    // Background-time assertion around payment dispatch
    // ------------------------------------------------------------------

    /// Taken while `inFlightPayments > 0`: if the user backgrounds the app
    /// mid-payment, iOS grants the process extra time so the RPC (and the
    /// signer behind it) can finish instead of being suspended with an HTLC
    /// half-dispatched.
    private func beginBackgroundHold() {
        guard bgTask == .invalid else { return }
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "payment-dispatch") { [weak self] in
            // Expiration runs on the main thread; the assertion MUST be
            // released here or iOS kills the process.
            MainActor.assumeIsolated {
                self?.endBackgroundHold()
            }
        }
    }

    private func endBackgroundHold() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }
}
