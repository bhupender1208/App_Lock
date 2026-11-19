package com.example.app_lock

import android.accessibilityservice.AccessibilityServiceInfo
import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import androidx.biometric.BiometricManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.Collator

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInstalledApps" -> result.success(getInstalledApps())
                "getProtectedApps" ->
                    result.success(AppLockStorage.protectedApps(this).toList())
                "getSettings" -> result.success(AppLockStorage.settings(this))
                "setBooleanSetting" -> {
                    val arguments = call.arguments as? Map<*, *>
                    val key = arguments?.get("key") as? String
                    val value = arguments?.get("value") as? Boolean
                    if (key == null || value == null) {
                        result.error(
                            "invalid_arguments",
                            "Expected a setting key and boolean value.",
                            null,
                        )
                    } else if (
                        key == "biometricEnabled" &&
                        value &&
                        BiometricManager.from(this).canAuthenticate(
                            BiometricManager.Authenticators.BIOMETRIC_WEAK,
                        ) != BiometricManager.BIOMETRIC_SUCCESS
                    ) {
                        result.error(
                            "biometric_unavailable",
                            "Set up fingerprint or face unlock on this device first.",
                            null,
                        )
                    } else {
                        try {
                            AppLockStorage.setBooleanSetting(this, key, value)
                            result.success(null)
                        } catch (error: IllegalArgumentException) {
                            result.error("invalid_setting", error.message, null)
                        }
                    }
                }
                "setAntiUninstallProtection" -> {
                    val enabled = call.arguments as? Boolean
                    if (enabled == null) {
                        result.error("invalid_arguments", "Expected a boolean.", null)
                    } else {
                        val manager =
                            getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
                        val admin = AppLockDeviceAdminReceiver.component(this)
                        if (enabled && !manager.isAdminActive(admin)) {
                            startActivity(
                                Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                                    .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                                    .putExtra(
                                        DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                                        getString(R.string.device_admin_description),
                                    ),
                            )
                        } else if (!enabled && manager.isAdminActive(admin)) {
                            manager.removeActiveAdmin(admin)
                        }
                        result.success(manager.isAdminActive(admin))
                    }
                }
                "setBackend" -> {
                    val backend = call.arguments as? String
                    if (backend == null || backend !in setOf(
                            "Accessibility Service",
                            "Usage Statistics",
                            "Shizuku Service",
                        )
                    ) {
                        result.error("invalid_backend", "Unsupported backend.", null)
                    } else {
                        AppLockStorage.setBackend(this, backend)
                        syncBackend()
                        result.success(null)
                    }
                }
                "isBackendReady" -> result.success(isBackendReady())
                "syncBackend" -> result.success(syncBackend())
                "isUsageAccessGranted" -> result.success(isUsageAccessGranted())
                "isOverlayPermissionGranted" ->
                    result.success(Settings.canDrawOverlays(this))
                "openUsageAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }
                "openOverlaySettings" -> {
                    startActivity(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName"),
                        ),
                    )
                    result.success(null)
                }
                "setProtectedApps" -> {
                    val packages = (call.arguments as? List<*>)
                        ?.filterIsInstance<String>()
                    if (packages == null) {
                        result.error("invalid_arguments", "Expected app package names.", null)
                    } else {
                        AppLockStorage.setProtectedApps(this, packages.toSet())
                        syncBackend()
                        result.success(null)
                    }
                }
                "isAccessibilityServiceEnabled" ->
                    result.success(isAppLockAccessibilityEnabled())
                "openAccessibilitySettings" -> {
                    startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                    result.success(null)
                }
                "isAppLockEnabled" -> result.success(AppLockStorage.isEnabled(this))
                "setAppLockEnabled" -> {
                    val enabled = call.arguments as? Boolean
                    if (enabled == null) {
                        result.error("invalid_arguments", "Expected a boolean.", null)
                    } else {
                        AppLockStorage.setEnabled(this, enabled)
                        syncBackend()
                        result.success(null)
                    }
                }
                "hasPin" -> result.success(AppLockStorage.hasPin(this))
                "setPin" -> {
                    val pin = call.arguments as? String
                    if (pin == null || !Regex("^\\d{4}$").matches(pin)) {
                        result.error("invalid_pin", "PIN must contain exactly four digits.", null)
                    } else {
                        AppLockStorage.setPin(this, pin)
                        result.success(true)
                    }
                }
                "validatePin" -> {
                    val pin = call.arguments as? String
                    if (AppLockStorage.lockoutRemainingMillis(this) > 0L) {
                        result.success(false)
                    } else if (pin != null && AppLockStorage.isPinValid(this, pin)) {
                        AppLockStorage.clearFailedPinAttempts(this)
                        result.success(true)
                    } else {
                        AppLockStorage.recordFailedPinAttempt(this)
                        result.success(false)
                    }
                }
                "getPinLockoutRemaining" ->
                    result.success(AppLockStorage.lockoutRemainingMillis(this))
                "setUnlockDuration" -> {
                    val duration = call.arguments as? String
                    if (duration == null) {
                        result.error("invalid_arguments", "Expected an unlock duration.", null)
                    } else {
                        try {
                            AppLockStorage.setUnlockDuration(this, duration)
                            result.success(null)
                        } catch (error: IllegalArgumentException) {
                            result.error("invalid_duration", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun getInstalledApps(): List<Map<String, String>> {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val collator = Collator.getInstance()
        return packageManager.queryIntentActivities(intent, 0)
            .map { it.activityInfo.applicationInfo }
            .filter { it.packageName != packageName }
            .distinctBy { it.packageName }
            .map { info ->
                mapOf(
                    "packageName" to info.packageName,
                    "name" to packageManager.getApplicationLabel(info).toString(),
                )
            }
            .sortedWith { first, second ->
                collator.compare(first["name"], second["name"])
            }
    }

    private fun isAppLockAccessibilityEnabled(): Boolean {
        val manager = getSystemService(ACCESSIBILITY_SERVICE) as AccessibilityManager
        return manager.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_ALL_MASK,
        ).any { info ->
            info.resolveInfo.serviceInfo.packageName == packageName &&
                info.resolveInfo.serviceInfo.name.endsWith("AppLockAccessibilityService")
        }
    }

    private fun isUsageAccessGranted(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        @Suppress("DEPRECATION")
        return appOps.checkOpNoThrow(
            AppOpsManager.OPSTR_GET_USAGE_STATS,
            Process.myUid(),
            packageName,
        ) == AppOpsManager.MODE_ALLOWED
    }

    private fun isBackendReady(): Boolean = when (AppLockStorage.backend(this)) {
        "Accessibility Service" -> isAppLockAccessibilityEnabled()
        "Usage Statistics" ->
            isUsageAccessGranted() && Settings.canDrawOverlays(this)
        else -> false
    }

    private fun syncBackend(): Boolean {
        if (
            AppLockStorage.backend(this) == "Usage Statistics" &&
            AppLockStorage.isEnabled(this) &&
            isUsageAccessGranted() &&
            Settings.canDrawOverlays(this)
        ) {
            val intent = Intent(this, UsageStatsLockService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            return true
        }
        stopService(Intent(this, UsageStatsLockService::class.java))
        return isBackendReady()
    }

    companion object {
        private const val CHANNEL = "com.example.app_lock/app_lock"
    }
}
