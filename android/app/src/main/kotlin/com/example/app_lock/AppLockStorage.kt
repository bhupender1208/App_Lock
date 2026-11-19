package com.example.app_lock

import android.content.Context
import java.security.MessageDigest
import java.security.SecureRandom

internal object AppLockStorage {
    private const val PREFS_NAME = "app_lock_settings"
    private const val KEY_PROTECTED_APPS = "protected_apps"
    private const val KEY_ENABLED = "lock_enabled"
    private const val KEY_PIN_HASH = "pin_hash"
    private const val KEY_PIN_SALT = "pin_salt"
    private const val KEY_UNLOCKED_PACKAGE = "unlocked_package"
    private const val KEY_UNLOCK_EXPIRES = "unlock_expires"
    private const val KEY_IMMEDIATE_UNLOCKED_PACKAGE = "immediate_unlocked_package"
    private const val KEY_UNLOCK_DURATION = "unlock_duration"
    private const val KEY_FAILED_PIN_ATTEMPTS = "failed_pin_attempts"
    private const val KEY_PIN_LOCKOUT_UNTIL = "pin_lockout_until"
    private const val KEY_BACKEND = "backend"
    private const val KEY_BIOMETRIC_ENABLED = "biometric_enabled"
    private const val KEY_HAPTIC_ENABLED = "haptic_enabled"
    private const val KEY_UNLOCK_ALL_PROTECTED_APPS = "unlock_all_protected_apps"

    private fun preferences(context: Context) =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun protectedApps(context: Context): Set<String> =
        preferences(context).getStringSet(KEY_PROTECTED_APPS, emptySet())
            ?.toSet() ?: emptySet()

    fun setProtectedApps(context: Context, packages: Set<String>) {
        preferences(context).edit().putStringSet(KEY_PROTECTED_APPS, packages).apply()
        AppLockAccessibilityService.instance?.refreshProtectedPackages()
    }

    fun isEnabled(context: Context): Boolean =
        preferences(context).getBoolean(KEY_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        preferences(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
    }

    fun backend(context: Context): String =
        preferences(context).getString(KEY_BACKEND, "Usage Statistics")
            ?: "Usage Statistics"

    fun setBackend(context: Context, backend: String) {
        preferences(context).edit().putString(KEY_BACKEND, backend).apply()
    }

    fun settings(context: Context): Map<String, Any> {
        val prefs = preferences(context)
        return mapOf(
            "backend" to backend(context),
            "biometricEnabled" to prefs.getBoolean(KEY_BIOMETRIC_ENABLED, false),
            "hapticEnabled" to prefs.getBoolean(KEY_HAPTIC_ENABLED, false),
            "antiUninstallEnabled" to AppLockDeviceAdminReceiver.isActive(context),
            "unlockAllProtectedApps" to prefs.getBoolean(
                KEY_UNLOCK_ALL_PROTECTED_APPS,
                false,
            ),
            "unlockDuration" to prefs.getString(
                KEY_UNLOCK_DURATION,
                "Until screen off",
            ).orEmpty(),
        )
    }

    fun setBooleanSetting(context: Context, key: String, value: Boolean) {
        val preferenceKey = when (key) {
            "biometricEnabled" -> KEY_BIOMETRIC_ENABLED
            "hapticEnabled" -> KEY_HAPTIC_ENABLED
            "unlockAllProtectedApps" -> KEY_UNLOCK_ALL_PROTECTED_APPS
            else -> throw IllegalArgumentException("Unknown setting: $key")
        }
        preferences(context).edit().putBoolean(preferenceKey, value).apply()
    }

    fun unlockAllProtectedApps(context: Context): Boolean =
        preferences(context).getBoolean(KEY_UNLOCK_ALL_PROTECTED_APPS, false)

    fun isBiometricEnabled(context: Context): Boolean =
        preferences(context).getBoolean(KEY_BIOMETRIC_ENABLED, false)

    fun isHapticEnabled(context: Context): Boolean =
        preferences(context).getBoolean(KEY_HAPTIC_ENABLED, false)

    fun hasPin(context: Context): Boolean =
        preferences(context).contains(KEY_PIN_HASH)

    fun setPin(context: Context, pin: String) {
        val prefs = preferences(context)
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        prefs.edit()
            .putString(KEY_PIN_SALT, salt.toHex())
            .putString(KEY_PIN_HASH, hashPin(pin, salt))
            .apply()
    }

    fun isPinValid(context: Context, pin: String): Boolean {
        val prefs = preferences(context)
        val salt = prefs.getString(KEY_PIN_SALT, null)?.hexToBytes() ?: return false
        val expected = prefs.getString(KEY_PIN_HASH, null) ?: return false
        val actual = hashPin(pin, salt)
        return MessageDigest.isEqual(
            expected.toByteArray(Charsets.UTF_8),
            actual.toByteArray(Charsets.UTF_8),
        )
    }

    fun setUnlockDuration(context: Context, duration: String) {
        require(
            duration in setOf(
                "Until screen off",
                "Immediately",
                "After 1 minute",
                "After 5 minutes",
                "After 10 minutes",
                "After 15 minutes",
                "After 30 minutes",
                "After 1 hour",
            ),
        ) { "Unsupported unlock duration." }
        preferences(context).edit().putString(KEY_UNLOCK_DURATION, duration).apply()
    }

    fun unlock(context: Context, packageName: String): Boolean {
        val prefs = preferences(context)
        val duration = prefs.getString(KEY_UNLOCK_DURATION, "Until screen off")
            ?: "Until screen off"
        if (duration == "Immediately") {
            if (
                !unlockAllProtectedApps(context) &&
                backend(context) == "Accessibility Service" &&
                AppLockAccessibilityService.instance
                    ?.allowUntilAppChanges(packageName) == true
            ) {
                clearUnlock(context)
                return true
            }
            prefs.edit()
                .putString(KEY_IMMEDIATE_UNLOCKED_PACKAGE, packageName)
                .putString(KEY_UNLOCKED_PACKAGE, packageName)
                .putLong(KEY_UNLOCK_EXPIRES, Long.MAX_VALUE)
                .apply()
            return true
        }

        val durationMillis = when (duration) {
            "After 1 minute" -> 60_000L
            "After 5 minutes" -> 5 * 60_000L
            "After 10 minutes" -> 10 * 60_000L
            "After 15 minutes" -> 15 * 60_000L
            "After 30 minutes" -> 30 * 60_000L
            "After 1 hour" -> 60 * 60_000L
            else -> 0L
        }
        val expiresAt = if (durationMillis == 0L) {
            Long.MAX_VALUE
        } else {
            System.currentTimeMillis() + durationMillis
        }
        prefs.edit()
            .remove(KEY_IMMEDIATE_UNLOCKED_PACKAGE)
            .putString(KEY_UNLOCKED_PACKAGE, packageName)
            .putLong(KEY_UNLOCK_EXPIRES, expiresAt)
            .apply()
        return true
    }

    fun immediateUnlockPackage(context: Context): String? =
        preferences(context).getString(KEY_IMMEDIATE_UNLOCKED_PACKAGE, null)

    fun isTemporarilyUnlocked(context: Context, packageName: String): Boolean {
        val prefs = preferences(context)
        val expiresAt = prefs.getLong(KEY_UNLOCK_EXPIRES, 0L)
        if (expiresAt != Long.MAX_VALUE && expiresAt <= System.currentTimeMillis()) {
            clearUnlock(context)
            return false
        }
        val unlockedPackage = prefs.getString(KEY_UNLOCKED_PACKAGE, null) ?: return false
        return unlockedPackage == packageName ||
            (unlockAllProtectedApps(context) && packageName in protectedApps(context))
    }

    fun clearUnlock(context: Context) {
        preferences(context).edit()
            .remove(KEY_UNLOCKED_PACKAGE)
            .remove(KEY_UNLOCK_EXPIRES)
            .remove(KEY_IMMEDIATE_UNLOCKED_PACKAGE)
            .apply()
    }

    fun lockoutRemainingMillis(context: Context): Long {
        val prefs = preferences(context)
        if (!prefs.contains(KEY_PIN_LOCKOUT_UNTIL)) return 0L

        val remaining = prefs.getLong(KEY_PIN_LOCKOUT_UNTIL, 0L) -
            System.currentTimeMillis()
        if (remaining <= 0L) {
            prefs.edit()
                .remove(KEY_PIN_LOCKOUT_UNTIL)
                .remove(KEY_FAILED_PIN_ATTEMPTS)
                .apply()
            return 0L
        }

        return remaining
    }

    fun recordFailedPinAttempt(context: Context): Long {
        val prefs = preferences(context)
        val remaining = lockoutRemainingMillis(context)
        if (remaining > 0L) return remaining

        val attempts = prefs.getInt(KEY_FAILED_PIN_ATTEMPTS, 0) + 1
        if (attempts >= 5) {
            prefs.edit()
                .putInt(KEY_FAILED_PIN_ATTEMPTS, 0)
                .putLong(
                    KEY_PIN_LOCKOUT_UNTIL,
                    System.currentTimeMillis() + 30_000L,
                )
                .apply()
            return 30_000L
        }

        prefs.edit().putInt(KEY_FAILED_PIN_ATTEMPTS, attempts).apply()
        return 0L
    }

    fun clearFailedPinAttempts(context: Context) {
        preferences(context).edit()
            .remove(KEY_FAILED_PIN_ATTEMPTS)
            .remove(KEY_PIN_LOCKOUT_UNTIL)
            .apply()
    }

    private fun hashPin(pin: String, salt: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256")
        return digest.digest(salt + pin.toByteArray(Charsets.UTF_8)).toHex()
    }

    private fun ByteArray.toHex(): String =
        joinToString(separator = "") { byte -> "%02x".format(byte) }

    private fun String.hexToBytes(): ByteArray? {
        if (length % 2 != 0) return null
        return ByteArray(length / 2) { index ->
            val byte = substring(index * 2, index * 2 + 2).toIntOrNull(16)
                ?: return null
            byte.toByte()
        }
    }
}
