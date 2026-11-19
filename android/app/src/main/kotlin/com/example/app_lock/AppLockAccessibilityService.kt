package com.example.app_lock

import android.accessibilityservice.AccessibilityService
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.inputmethod.InputMethodManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import android.os.Handler
import android.os.Looper

class AppLockAccessibilityService : AccessibilityService() {
    private val lockoutHandler = Handler(Looper.getMainLooper())
    private var lockoutRunnable: Runnable? = null
    private val homePackages = mutableSetOf<String>()
    private val inputMethodPackages = mutableSetOf<String>()
    private var protectedPackages = emptySet<String>()
    private var overlay: FrameLayout? = null
    private var overlayPackage: String? = null
    private var immediatelyUnlockedPackage: String? = null
    private var screenOffReceiverRegistered = false

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                AppLockStorage.clearUnlock(this@AppLockAccessibilityService)
                immediatelyUnlockedPackage = null
                removeLockOverlay()
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        refreshProtectedPackages()
        loadHomePackages()
        loadInputMethodPackages()
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOffReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(screenOffReceiver, filter)
        }
        screenOffReceiverRegistered = true
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (AppLockStorage.backend(this) != "Accessibility Service") return
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val foregroundPackage = event.packageName?.toString()?.takeIf(String::isNotBlank)
            ?: return

        if (foregroundPackage == "com.android.systemui") return
        if (foregroundPackage in inputMethodPackages) return

        if (foregroundPackage == packageName && overlay != null) return

        val immediateUnlockPackage = AppLockStorage.immediateUnlockPackage(this)
            ?: immediatelyUnlockedPackage
        if (immediateUnlockPackage != null) {
            val unlockContinues = if (AppLockStorage.unlockAllProtectedApps(this)) {
                foregroundPackage in protectedPackages
            } else {
                foregroundPackage == immediateUnlockPackage
            }
            if (!unlockContinues) {
                AppLockStorage.clearUnlock(this)
                immediatelyUnlockedPackage = null
            }
        }

        if (foregroundPackage == packageName || foregroundPackage in homePackages) {
            removeLockOverlay()
            return
        }

        if (overlayPackage != null && overlayPackage != foregroundPackage) {
            removeLockOverlay()
        }

        if (!AppLockStorage.isEnabled(this) ||
            !AppLockStorage.hasPin(this) ||
            foregroundPackage !in protectedPackages
        ) {
            return
        }
        if (immediatelyUnlockedPackage == foregroundPackage ||
            AppLockStorage.isTemporarilyUnlocked(this, foregroundPackage)
        ) {
            return
        }
        showLockOverlay(foregroundPackage)
    }

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        if (screenOffReceiverRegistered) {
            unregisterReceiver(screenOffReceiver)
            screenOffReceiverRegistered = false
        }
        removeLockOverlay()
        if (instance === this) instance = null
        super.onDestroy()
    }

    fun refreshProtectedPackages() {
        protectedPackages = AppLockStorage.protectedApps(this)
        if (overlayPackage !in protectedPackages) removeLockOverlay()
    }

    fun allowUntilAppChanges(packageName: String): Boolean {
        immediatelyUnlockedPackage = packageName
        return true
    }

    fun dismissLockOverlay() {
        removeLockOverlay()
    }

    private fun loadHomePackages() {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        homePackages.clear()
        @Suppress("DEPRECATION")
        val resolved = packageManager.queryIntentActivities(intent, 0)
        homePackages.addAll(resolved.map { it.activityInfo.packageName })
    }

    private fun loadInputMethodPackages() {
        val inputMethodManager =
            getSystemService(INPUT_METHOD_SERVICE) as InputMethodManager
        inputMethodPackages.clear()
        inputMethodPackages.addAll(
            inputMethodManager.enabledInputMethodList.map { it.packageName },
        )
    }

    private fun showLockOverlay(targetPackage: String) {
        if (overlayPackage == targetPackage && overlay != null) return
        removeLockOverlay()

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(230, 230, 232))
            isFocusableInTouchMode = true
            setOnTouchListener { _, _ -> true }
        }
        val title = TextView(this).apply {
            text = "Enter password to continue"
            textSize = 26f
            setTextColor(Color.BLACK)
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
        }
        val subtitle = TextView(this).apply {
            text = ""
            textSize = 14f
            setTextColor(Color.rgb(94, 98, 109))
        }
        val enteredPin = StringBuilder()
        val keypadKeys = mutableListOf<TextView>()
        val keySize = minOf(
            dp(80),
            (resources.displayMetrics.widthPixels - dp(64)) / 3,
        )

        fun setKeypadEnabled(enabled: Boolean) {
            keypadKeys.forEach { key ->
                key.isEnabled = enabled
                key.alpha = if (enabled) 1f else 0.55f
            }
        }

        fun updateLockoutUi() {
            lockoutRunnable?.let { lockoutHandler.removeCallbacks(it) }
            val remaining = AppLockStorage.lockoutRemainingMillis(this)

            if (remaining <= 0L) {
                setKeypadEnabled(true)
                subtitle.text = ""
                lockoutRunnable = null
                return
            }

            setKeypadEnabled(false)
            val seconds = (remaining + 999L) / 1000L
            subtitle.text =
                "Too many incorrect attempts. Try again in $seconds seconds."

            val runnable = object : Runnable {
                override fun run() {
                    updateLockoutUi()
                }
            }
            lockoutRunnable = runnable
            lockoutHandler.postDelayed(runnable, 1000L)
        }

        fun unlock() {
            if (AppLockStorage.lockoutRemainingMillis(this) > 0L) {
                updateLockoutUi()
                return
            }
            if (enteredPin.length != 4) return

            val pin = enteredPin.toString()
            enteredPin.clear()
            if (AppLockStorage.isPinValid(this, pin)) {
                AppLockStorage.clearFailedPinAttempts(this)
                AppLockStorage.unlock(this, targetPackage)
                removeLockOverlay()
            } else {
                val remaining = AppLockStorage.recordFailedPinAttempt(this)
                if (remaining > 0L) {
                    updateLockoutUi()
                } else {
                    subtitle.text = "Incorrect PIN"
                }
            }
        }

        fun addKey(
            label: String,
            contentDescription: String,
            highlighted: Boolean = false,
            onClick: () -> Unit,
        ): TextView {
            val key = TextView(this).apply {
                text = label
                textSize = if (label.length == 1) 32f else 30f
                setTextColor(
                    if (highlighted) Color.rgb(48, 75, 128)
                    else Color.rgb(59, 62, 74),
                )
                gravity = Gravity.CENTER
                typeface = Typeface.create("sans-serif", Typeface.NORMAL)
                this.contentDescription = contentDescription
                background = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(
                        if (highlighted) Color.rgb(220, 228, 250)
                        else Color.rgb(250, 248, 255),
                    )
                }
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    if (AppLockStorage.isHapticEnabled(this@AppLockAccessibilityService)) {
                        performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    }
                    onClick()
                }
            }
            keypadKeys.add(key)
            return key
        }

        val keypad = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        val rows = listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
        )
        rows.forEach { labels ->
            val row = LinearLayout(this).apply {
                gravity = Gravity.CENTER
            }
            labels.forEach { label ->
                val key = addKey(label, label) {
                    if (AppLockStorage.lockoutRemainingMillis(this) == 0L) {
                        subtitle.text = ""
                        enteredPin.append(label)
                        if (enteredPin.length == 4) unlock()
                    } else {
                        updateLockoutUi()
                    }
                }
                row.addView(
                    key,
                    LinearLayout.LayoutParams(keySize, keySize).apply {
                        setMargins(dp(4), dp(4), dp(4), dp(4))
                    },
                )
            }
            keypad.addView(row)
        }

        val finalRow = LinearLayout(this).apply {
            gravity = Gravity.CENTER
        }
        val deleteKey = addKey("⌫", "Delete last digit", highlighted = true) {
            if (enteredPin.isNotEmpty()) enteredPin.deleteCharAt(enteredPin.lastIndex)
        }
        val zeroKey = addKey("0", "0") {
            if (AppLockStorage.lockoutRemainingMillis(this) == 0L) {
                subtitle.text = ""
                enteredPin.append('0')
                if (enteredPin.length == 4) unlock()
            } else {
                updateLockoutUi()
            }
        }
        val submitKey = addKey("›", "Submit PIN", highlighted = true) {
            unlock()
        }
        listOf(deleteKey, zeroKey, submitKey).forEach { key ->
            finalRow.addView(
                key,
                LinearLayout.LayoutParams(keySize, keySize).apply {
                    setMargins(dp(4), dp(4), dp(4), dp(4))
                },
            )
        }
        keypad.addView(finalRow)

        if (AppLockStorage.isBiometricEnabled(this)) {
            val biometricButton = TextView(this).apply {
                text = "Use fingerprint or face unlock"
                textSize = 15f
                gravity = Gravity.CENTER
                setTextColor(Color.rgb(48, 75, 128))
                setOnClickListener {
                    val intent = Intent(
                        this@AppLockAccessibilityService,
                        BiometricUnlockActivity::class.java,
                    ).apply {
                        putExtra(BiometricUnlockActivity.EXTRA_PACKAGE, targetPackage)
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivity(intent)
                }
            }
            root.addView(
                biometricButton,
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    dp(48),
                    Gravity.BOTTOM,
                ).apply { bottomMargin = dp(340) },
            )
        }

        root.addView(
            title,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.START,
            ).apply {
                leftMargin = dp(24)
                topMargin = dp(60)
            },
        )
        root.addView(
            subtitle,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP or Gravity.START,
            ).apply {
                leftMargin = dp(24)
                rightMargin = dp(24)
                topMargin = dp(100)
            },
        )
        root.addView(
            keypad,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
            ).apply {
                bottomMargin = dp(28)
            },
        )

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            softInputMode = WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE or
                WindowManager.LayoutParams.SOFT_INPUT_STATE_ALWAYS_HIDDEN
        }

        val windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        windowManager.addView(root, params)
        overlay = root
        overlayPackage = targetPackage
        updateLockoutUi()
    }

    private fun removeLockOverlay() {
        lockoutRunnable?.let { lockoutHandler.removeCallbacks(it) }
        lockoutRunnable = null

        val currentOverlay = overlay ?: return
        overlay = null
        overlayPackage = null
        (getSystemService(WINDOW_SERVICE) as? WindowManager)
            ?.removeView(currentOverlay)
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        @Volatile
        var instance: AppLockAccessibilityService? = null
            private set
    }
}
