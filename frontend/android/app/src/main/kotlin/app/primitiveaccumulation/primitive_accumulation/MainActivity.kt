package app.primitiveaccumulation.primitive_accumulation

import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.hardware.fingerprint.FingerprintManager
import android.os.Build
import android.os.CancellationSignal
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val alias = "ledger.biometric.v1"
    private val prefs by lazy { getSharedPreferences(alias, MODE_PRIVATE) }
    private val keys get() = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    private var pending: CancellationSignal? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "primitive_accumulation/biometric")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "available" -> result.success(available())
                        "enabled" -> result.success(prefs.contains("ciphertext") && keys.containsAlias(alias))
                        "disable" -> {
                            keys.deleteEntry(alias)
                            check(prefs.edit().clear().commit())
                            result.success(null)
                        }
                        "enable", "unlock" -> {
                            check(Build.VERSION.SDK_INT >= 28 && pending == null)
                            val password = if (call.method == "enable") call.arguments as String else null
                            authenticate(password, result)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    result.error("unavailable", null, null)
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun available(): Boolean = when {
        Build.VERSION.SDK_INT >= 30 -> getSystemService(BiometricManager::class.java)
            .canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG) == BiometricManager.BIOMETRIC_SUCCESS
        Build.VERSION.SDK_INT >= 28 -> getSystemService(FingerprintManager::class.java)?.hasEnrolledFingerprints() == true
        else -> false
    }

    private fun newKey(): SecretKey {
        val spec = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setUserAuthenticationRequired(true)
            .setInvalidatedByBiometricEnrollment(true)
            .build()
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(spec)
            generateKey()
        }
    }

    @android.annotation.TargetApi(28)
    private fun authenticate(password: String?, result: MethodChannel.Result) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        if (password != null) {
            cipher.init(Cipher.ENCRYPT_MODE, newKey())
        } else {
            val iv = Base64.decode(prefs.getString("iv", null), Base64.NO_WRAP)
            cipher.init(Cipher.DECRYPT_MODE, keys.getKey(alias, null), GCMParameterSpec(128, iv))
        }
        val signal = CancellationSignal()
        fun finish(action: () -> Unit) {
            if (pending !== signal) return
            pending = null
            action()
        }
        val prompt = BiometricPrompt.Builder(this)
            .setTitle(if (password == null) "解锁本机账本" else "开启生物识别解锁")
            .setNegativeButton("取消", mainExecutor) { _, _ ->
                finish { result.error("cancelled", null, null) }
            }.build()
        pending = signal
        try {
            prompt.authenticate(BiometricPrompt.CryptoObject(cipher), signal, mainExecutor,
                object : BiometricPrompt.AuthenticationCallback() {
                    override fun onAuthenticationError(code: Int, message: CharSequence) {
                        finish { result.error("authentication", null, null) }
                    }
                    override fun onAuthenticationSucceeded(auth: BiometricPrompt.AuthenticationResult) {
                        finish {
                            try {
                                check(!signal.isCanceled)
                                val authorized = requireNotNull(auth.cryptoObject?.cipher)
                                if (password != null) {
                                    val encrypted = authorized.doFinal(password.toByteArray(Charsets.UTF_8))
                                    check(prefs.edit()
                                        .putString("ciphertext", Base64.encodeToString(encrypted, Base64.NO_WRAP))
                                        .putString("iv", Base64.encodeToString(authorized.iv, Base64.NO_WRAP))
                                        .commit())
                                    result.success(null)
                                } else {
                                    val encrypted = Base64.decode(prefs.getString("ciphertext", null), Base64.NO_WRAP)
                                    result.success(String(authorized.doFinal(encrypted), Charsets.UTF_8))
                                }
                            } catch (_: Exception) {
                                result.error("credential", null, null)
                            }
                        }
                    }
                })
        } catch (error: Exception) {
            pending = null
            throw error
        }
    }

    override fun onStop() {
        pending?.cancel()
        super.onStop()
    }
}
