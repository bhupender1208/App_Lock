package com.example.app_lock

import android.os.Bundle
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

class BiometricUnlockActivity : FragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val targetPackage = intent.getStringExtra(EXTRA_PACKAGE)
        if (targetPackage.isNullOrBlank()) {
            finish()
            return
        }

        if (
            BiometricManager.from(this).canAuthenticate(
                BiometricManager.Authenticators.BIOMETRIC_WEAK,
            ) != BiometricManager.BIOMETRIC_SUCCESS
        ) {
            finish()
            return
        }

        val prompt = BiometricPrompt(
            this,
            ContextCompat.getMainExecutor(this),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult,
                ) {
                    AppLockStorage.unlock(this@BiometricUnlockActivity, targetPackage)
                    AppLockAccessibilityService.instance?.dismissLockOverlay()
                    finish()
                }

                override fun onAuthenticationError(errorCode: Int, errString: CharSequence) {
                    finish()
                }
            },
        )
        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle("Unlock protected app")
                .setSubtitle("Verify your fingerprint or face")
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK)
                .setNegativeButtonText("Cancel")
                .build(),
        )
    }

    companion object {
        const val EXTRA_PACKAGE = "target_package"
    }
}
