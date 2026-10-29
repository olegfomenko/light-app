package app.light.wallet.data

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Secret storage following current Android best practice:
 *
 *  - A 256-bit AES key is generated inside the **Android Keystore**. The key
 *    is StrongBox-backed when the device provides a secure element, otherwise
 *    it lives in the TEE; the key material never leaves secure hardware and is
 *    marked unlocked-device-required so it cannot be used while the phone is
 *    locked. The app only ever asks the Keystore to encrypt/decrypt.
 *  - Data is encrypted with AES/GCM (fresh random IV per write, IV stored
 *    alongside the ciphertext) and kept in app-private SharedPreferences.
 *  - Jetpack's EncryptedSharedPreferences is intentionally NOT used: the
 *    androidx.security:security-crypto library was deprecated in 2024 and
 *    Google's guidance is to use the Keystore directly, which is what we do.
 *  - `android:allowBackup="false"` in the manifest keeps ciphertext (and
 *    prefs) out of device backups.
 *
 * Possible hardening later: setUserAuthenticationRequired(true) +
 * BiometricPrompt to additionally gate the seed behind a biometric prompt.
 */
class SecureStorage(context: Context) {

    private val prefs =
        context.getSharedPreferences("light_secure_store", Context.MODE_PRIVATE)

    // Non-secret settings live in PLAIN prefs. Routing them through the
    // Keystore was not just pointless — a StrongBox decrypt is a synchronous
    // secure-element round-trip (~100-500ms on real hardware), and these values
    // are read during UI composition on the main thread. Keystore work must
    // never sit on a UI path.
    private val plainPrefs =
        context.getSharedPreferences("light_prefs", Context.MODE_PRIVATE)

    companion object {
        private const val KEY_ALIAS = "lightapp_master_key"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORM = "AES/GCM/NoPadding"
        private const val TAG_BITS = 128

        const val K_MNEMONIC = "mnemonic"
        const val K_PASSPHRASE = "passphrase"
        const val K_NETWORK = "network"
        const val K_DEVICE_CREDS = "device_creds"
        const val K_DEV_CERT = "developer_cert"
        const val K_DEV_KEY = "developer_key"
        const val K_UNIT = "display_unit"
    }

    @Volatile
    private var cachedKey: SecretKey? = null

    // Synchronized: a check-then-generate race between two threads on a fresh
    // install could otherwise create the alias twice, and the second key would
    // silently replace the one that encrypted the first value — corrupting it.
    @Synchronized
    private fun masterKey(): SecretKey {
        // Cache the key HANDLE (not key material — that never leaves the
        // Keystore). Reloading the KeyStore per call is expensive, and crypto
        // ops still go to the secure hardware each time regardless.
        cachedKey?.let { return it }
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        val key = (ks.getKey(KEY_ALIAS, null) as? SecretKey) ?: generateKey(strongBox = true)
        cachedKey = key
        return key
    }

    private fun generateKey(strongBox: Boolean): SecretKey {
        val spec = KeyGenParameterSpec.Builder(
            KEY_ALIAS,
            KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
        )
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setKeySize(256)
            // Key is unusable while the device is locked (the seed is only ever
            // decrypted with the app in the foreground, i.e. unlocked).
            .setUnlockedDeviceRequired(true)
            .apply { if (strongBox) setIsStrongBoxBacked(true) }
            .build()
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        return try {
            generator.init(spec)
            generator.generateKey()
        } catch (e: Exception) {
            // No StrongBox on this device — retry in the TEE. We never drop the
            // unlocked-device requirement.
            if (strongBox) generateKey(strongBox = false) else throw e
        }
    }

    private fun encrypt(plain: ByteArray): String {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, masterKey())
        val ct = cipher.doFinal(plain)
        val iv = cipher.iv
        return Base64.encodeToString(iv, Base64.NO_WRAP) + ":" +
            Base64.encodeToString(ct, Base64.NO_WRAP)
    }

    private fun decrypt(stored: String): ByteArray {
        val (ivB64, ctB64) = stored.split(":", limit = 2)
        val iv = Base64.decode(ivB64, Base64.NO_WRAP)
        val ct = Base64.decode(ctB64, Base64.NO_WRAP)
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.DECRYPT_MODE, masterKey(), GCMParameterSpec(TAG_BITS, iv))
        return cipher.doFinal(ct)
    }

    fun putBytes(key: String, value: ByteArray) {
        prefs.edit().putString(key, encrypt(value)).apply()
    }

    fun getBytes(key: String): ByteArray? =
        prefs.getString(key, null)?.let {
            runCatching { decrypt(it) }.getOrNull()
        }

    fun putString(key: String, value: String) = putBytes(key, value.toByteArray())

    fun getString(key: String): String? = getBytes(key)?.decodeToString()

    fun remove(key: String) {
        prefs.edit().remove(key).apply()
    }

    fun wipe() {
        prefs.edit().clear().apply()
        plainPrefs.edit().clear().apply()
    }

    // -- Wallet-specific accessors -----------------------------------------

    var mnemonic: String?
        get() = getString(K_MNEMONIC)
        set(v) = if (v == null) remove(K_MNEMONIC) else putString(K_MNEMONIC, v)

    var passphrase: String
        get() = getString(K_PASSPHRASE) ?: ""
        set(v) = putString(K_PASSPHRASE, v)

    var network: String
        get() = plainPrefs.getString(K_NETWORK, null) ?: "bitcoin"
        set(v) = plainPrefs.edit().putString(K_NETWORK, v).apply()

    var deviceCreds: ByteArray?
        get() = getBytes(K_DEVICE_CREDS)
        set(v) = if (v == null) remove(K_DEVICE_CREDS) else putBytes(K_DEVICE_CREDS, v)

    var developerCert: ByteArray?
        get() = getBytes(K_DEV_CERT)
        set(v) = if (v == null) remove(K_DEV_CERT) else putBytes(K_DEV_CERT, v)

    var developerKey: ByteArray?
        get() = getBytes(K_DEV_KEY)
        set(v) = if (v == null) remove(K_DEV_KEY) else putBytes(K_DEV_KEY, v)

    /** "sat" | "msat" | "btc" — a plain preference, deliberately NOT encrypted. */
    var displayUnit: String
        get() = plainPrefs.getString(K_UNIT, null) ?: "sat"
        set(v) = plainPrefs.edit().putString(K_UNIT, v).apply()

    /**
     * True when a wallet is stored, based on the *presence* of the ciphertext —
     * not on whether it currently decrypts. If the Keystore key was invalidated
     * (lock-screen change, restore) the seed is still there and must not be
     * treated as "no wallet", which would send the user to onboarding and let
     * [WalletRepository.setupWallet] overwrite the only copy of their seed.
     */
    fun hasWallet(): Boolean =
        prefs.contains(K_MNEMONIC) && prefs.contains(K_DEVICE_CREDS)

    /**
     * Move displayUnit/network out of the encrypted store (installed versions
     * kept them there). Call from a background coroutine at app start — this
     * touches the Keystore, so it must never run on the main thread. Idempotent;
     * best-effort (defaults are correct if the old values can't be decrypted).
     */
    fun migrateNonSecrets() {
        for (key in listOf(K_UNIT, K_NETWORK)) {
            if (!prefs.contains(key)) continue
            val migrated = if (plainPrefs.contains(key)) {
                true // already copied (or user already wrote a fresh value)
            } else {
                val old = runCatching { getString(key) }.getOrNull()
                if (old != null) {
                    // Re-check just before writing: a Settings write that landed
                    // during our (slow, StrongBox) decrypt must not be clobbered
                    // by the stale migrated value.
                    if (!plainPrefs.contains(key)) {
                        plainPrefs.edit().putString(key, old).apply()
                    }
                    true
                } else {
                    false // transient decrypt failure — retry on next launch
                }
            }
            // Only drop the ciphertext once the value provably lives in plain
            // prefs; removing it after a failed copy would lose the setting.
            if (migrated) prefs.edit().remove(key).apply()
        }
    }
}
