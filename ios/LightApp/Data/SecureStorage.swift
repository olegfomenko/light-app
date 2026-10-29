import Foundation
import Security

/// Secret storage following current iOS best practice:
///
///  - Secrets live in the **iOS Keychain** as `kSecClassGenericPassword`
///    items (service `"app.light.wallet"`, one item per key). Keychain data
///    is encrypted at rest with device keys wrapped by the Secure Enclave —
///    the iOS analogue of the Android Keystore's TEE/StrongBox-backed AES key.
///    Unlike Android we do not run AES/GCM ourselves: the Keychain *is* the
///    encrypted store, so there is no IV bookkeeping and no ciphertext blob
///    to babysit in preferences.
///  - Every item is written with
///    `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. That single attribute is
///    the parity of two separate Android decisions: *WhenUnlocked* mirrors
///    `setUnlockedDeviceRequired(true)` (the seed is only ever decrypted with
///    the app in the foreground, i.e. unlocked — the data is cryptographically
///    unavailable while the phone is locked), and *ThisDeviceOnly* mirrors
///    `android:allowBackup="false"` (the item is excluded from iCloud/iTunes
///    backups and can never be restored onto another device; keys derived from
///    this device's hardware UID wrap it).
///  - Non-secret settings live in **UserDefaults** — deliberately NOT in the
///    Keychain. Android learned this the hard way: routing plain preferences
///    through the secret store was not just pointless — a secure-element
///    round-trip is synchronous and these values are read during UI
///    composition on the main thread. Crypto-store work must never sit on a
///    UI path, so `displayUnit` and `network` stay in plain defaults.
///
/// Possible hardening later: `kSecAttrAccessControl` with
/// `.biometryCurrentSet` to additionally gate the seed behind Face ID / Touch
/// ID (the analogue of Android's `setUserAuthenticationRequired(true)` +
/// BiometricPrompt).
final class SecureStorage: @unchecked Sendable {

    /// Keychain service shared by every secret this app stores. `wipe()`
    /// deletes by service, so nothing else in the process may use it.
    private static let service = "app.light.wallet"

    static let kMnemonic = "mnemonic"
    static let kPassphrase = "passphrase"
    static let kNetwork = "network"
    static let kDeviceCreds = "device_creds"
    static let kDevCert = "developer_cert"
    static let kDevKey = "developer_key"
    static let kUnit = "display_unit"

    /// Plain, unencrypted preferences for the non-secrets. See the class doc:
    /// these are read on the main thread during view updates and must never
    /// touch the Keychain.
    private let plainPrefs: UserDefaults

    /// Serializes every Keychain mutation. The Keychain itself is
    /// thread-safe, but our write path is add-then-update-on-duplicate — a
    /// check-then-act sequence. On Android the equivalent race (two threads
    /// generating the master key on a fresh install) could silently corrupt
    /// the first value written; the lock closes the same class of race here.
    /// Keychain calls are cheap (no secure-element round-trip on the app's
    /// side), so a plain lock — usable from any thread, no main-actor
    /// requirement — is the right tool.
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.plainPrefs = defaults
        // iOS Keychain items OUTLIVE the app: deleting LightApp leaves the
        // seed behind, and a reinstall would silently resurrect the wallet —
        // Android has no such behavior ("uninstall = wipe" is the user's
        // mental model there). UserDefaults DO die with the app, so a missing
        // install marker next to surviving keychain items means this is a
        // fresh install over stale secrets: clear them. Recovering after a
        // reinstall means typing the written-down seed, exactly as on Android.
        if !defaults.bool(forKey: Self.kInstallMarker) {
            if hasWallet() { wipe() }
            defaults.set(true, forKey: Self.kInstallMarker)
        }
    }

    static let kInstallMarker = "installed_marker"

    // -- Keychain plumbing --------------------------------------------------

    /// Base query for one item: generic password, our service, one account
    /// per logical key. Everything else layers on top of this dictionary.
    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key,
        ]
    }

    /// Write-through: add, and on `errSecDuplicateItem` update in place. The
    /// accessibility class is (re)asserted on both paths so an item can never
    /// drift to a weaker protection level than
    /// `WhenUnlockedThisDeviceOnly` — we never drop the unlocked-device
    /// requirement.
    /// Returns whether the item provably landed in the Keychain. Callers
    /// storing the ONLY copy of a secret (the seed) must check this — a
    /// silently dropped write here would surface much later as unrecoverable
    /// fund loss, which is the one failure this store must never allow.
    @discardableResult
    private func keychainPut(_ key: String, _ value: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var add = baseQuery(key)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        add[kSecValueData as String] = value

        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [
                kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                kSecValueData as String: value,
            ]
            status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        }
        return status == errSecSuccess
    }

    /// Read-through. Any failure (item missing, or present but currently
    /// unreadable) reads as `nil` — mirroring the Android `runCatching`
    /// around decrypt. Callers that must distinguish "absent" from
    /// "unreadable" use `keychainContains` instead; see `hasWallet()`.
    private func keychainGet(_ key: String) -> Data? {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Presence check that asks for **attributes only** (`kSecReturnAttributes`,
    /// no `kSecReturnData`): it answers "does an item exist?" without asking
    /// the Keychain to hand over — and therefore decrypt — the payload. This
    /// is the load-bearing distinction for `hasWallet()`.
    private func keychainContains(_ key: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        var query = baseQuery(key)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        // errSecInteractionNotAllowed means the item exists but the device is
        // locked right now — that is still "present". Only a clean
        // errSecItemNotFound counts as absent.
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    private func keychainRemove(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    // -- Generic accessors (parity with the Kotlin surface) -----------------

    func putBytes(_ key: String, _ value: Data) {
        keychainPut(key, value)
    }

    /// Write-and-verify for secrets whose loss is unrecoverable: returns true
    /// only when the value was stored AND reads back byte-identical.
    func putBytesVerified(_ key: String, _ value: Data) -> Bool {
        keychainPut(key, value) && getBytes(key) == value
    }

    func getBytes(_ key: String) -> Data? {
        keychainGet(key)
    }

    func putString(_ key: String, _ value: String) {
        putBytes(key, Data(value.utf8))
    }

    func getString(_ key: String) -> String? {
        getBytes(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    func remove(_ key: String) {
        keychainRemove(key)
    }

    /// Erase everything: one `SecItemDelete` scoped to our service removes
    /// every secret in a single call, then the plain preferences go too.
    /// After `wipe()` the app is indistinguishable from a fresh install.
    func wipe() {
        lock.lock()
        let all: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
        ]
        SecItemDelete(all as CFDictionary)
        lock.unlock()

        plainPrefs.removeObject(forKey: Self.kNetwork)
        plainPrefs.removeObject(forKey: Self.kUnit)
    }

    // -- Wallet-specific accessors -----------------------------------------

    var mnemonic: String? {
        get { getString(Self.kMnemonic) }
        set {
            if let v = newValue { putString(Self.kMnemonic, v) } else { remove(Self.kMnemonic) }
        }
    }

    var passphrase: String {
        get { getString(Self.kPassphrase) ?? "" }
        set { putString(Self.kPassphrase, newValue) }
    }

    /// Greenlight network name. A plain preference, deliberately NOT in the
    /// Keychain — it is not a secret and it is read on the UI path.
    var network: String {
        get { plainPrefs.string(forKey: Self.kNetwork) ?? "bitcoin" }
        set { plainPrefs.set(newValue, forKey: Self.kNetwork) }
    }

    var deviceCreds: Data? {
        get { getBytes(Self.kDeviceCreds) }
        set {
            if let v = newValue { putBytes(Self.kDeviceCreds, v) } else { remove(Self.kDeviceCreds) }
        }
    }

    var developerCert: Data? {
        get { getBytes(Self.kDevCert) }
        set {
            if let v = newValue { putBytes(Self.kDevCert, v) } else { remove(Self.kDevCert) }
        }
    }

    var developerKey: Data? {
        get { getBytes(Self.kDevKey) }
        set {
            if let v = newValue { putBytes(Self.kDevKey, v) } else { remove(Self.kDevKey) }
        }
    }

    /// "sat" | "msat" | "btc" — a plain preference, deliberately NOT encrypted.
    var displayUnit: String {
        get { plainPrefs.string(forKey: Self.kUnit) ?? "sat" }
        set { plainPrefs.set(newValue, forKey: Self.kUnit) }
    }

    /// True when a wallet is stored, based on the *presence* of the Keychain
    /// items — not on whether they currently load. If an item exists but is
    /// momentarily unreadable (device locked at the instant of the query,
    /// keychain in a transient error state) the seed is still there and must
    /// not be treated as "no wallet", which would send the user to onboarding
    /// and let `WalletRepository.setupWallet` overwrite the only copy of
    /// their seed.
    func hasWallet() -> Bool {
        keychainContains(Self.kMnemonic) && keychainContains(Self.kDeviceCreds)
    }
}
