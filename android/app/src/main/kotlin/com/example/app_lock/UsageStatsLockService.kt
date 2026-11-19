package com.example.app_lock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView

class UsageStatsLockService : Service() {
    private lateinit var worker: HandlerThread
    private lateinit var handler: Handler
    private var window: FrameLayout? = null
    private var lockedPackage: String? = null
    private var foregroundPackage: String? = null
    private var eventCursor = 0L
    private var screenOffReceiverRegistered = false

    private val screenOffReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == Intent.ACTION_SCREEN_OFF) {
                AppLockStorage.clearUnlock(this@UsageStatsLockService)
                removeLockWindow()
            }
        }
    }

    private val poll = object : Runnable {
        override fun run() {
            if (
                AppLockStorage.backend(this@UsageStatsLockService) != "Usage Statistics" ||
                !AppLockStorage.isEnabled(this@UsageStatsLockService)
            ) {
                removeLockWindow()
                stopSelf()
                return
            }

            val now = System.currentTimeMillis()
            val usage = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val events = usage.queryEvents(eventCursor, now)
            val event = UsageEvents.Event()
            while (events.hasNextEvent()) {
                events.getNextEvent(event)
                when (event.eventType) {
                    UsageEvents.Event.ACTIVITY_RESUMED,
                    UsageEvents.Event.MOVE_TO_FOREGROUND,
                    -> foregroundPackage = event.packageName
                    UsageEvents.Event.ACTIVITY_PAUSED,
                    UsageEvents.Event.MOVE_TO_BACKGROUND,
                    -> if (foregroundPackage == event.packageName) {
                        foregroundPackage = null
                    }
                }
            }
            eventCursor = now

            val current = foregroundPackage
            val immediatelyUnlocked = AppLockStorage.immediateUnlockPackage(
                this@UsageStatsLockService,
            )
            val protectedApps = AppLockStorage.protectedApps(this@UsageStatsLockService)
            if (
                immediatelyUnlocked != null &&
                current != null &&
                current != immediatelyUnlocked &&
                current != packageName &&
                (!AppLockStorage.unlockAllProtectedApps(this@UsageStatsLockService) ||
                    current !in protectedApps)
            ) {
                AppLockStorage.clearUnlock(this@UsageStatsLockService)
            }
            if (current != lockedPackage) removeLockWindow()
            if (
                current != null &&
                current != packageName &&
                current in protectedApps &&
                AppLockStorage.hasPin(this@UsageStatsLockService) &&
                !AppLockStorage.isTemporarilyUnlocked(
                    this@UsageStatsLockService,
                    current,
                )
            ) {
                showLockWindow(current)
            }
            handler.postDelayed(this, POLL_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        isRunning = true
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenOffReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("DEPRECATION")
            registerReceiver(screenOffReceiver, filter)
        }
        screenOffReceiverRegistered = true
        worker = HandlerThread("app-lock-usage-monitor").apply { start() }
        handler = Handler(worker.looper)
        eventCursor = System.currentTimeMillis() - INITIAL_LOOKBACK_MS
        handler.post(poll)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        START_STICKY

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        worker.quitSafely()
        if (screenOffReceiverRegistered) {
            unregisterReceiver(screenOffReceiver)
            screenOffReceiverRegistered = false
        }
        removeLockWindow()
        isRunning = false
        super.onDestroy()
    }

    private fun showLockWindow(targetPackage: String) {
        if (lockedPackage == targetPackage && window != null) return
        removeLockWindow()

        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(230, 230, 232))
            isFocusableInTouchMode = true
            setOnTouchListener { _, _ -> true }
        }
        val title = TextView(this).apply {
            text = "Enter password to continue"
            textSize = 25f
            setTextColor(Color.BLACK)
            typeface = Typeface.create("sans-serif", Typeface.BOLD)
        }
        val subtitle = TextView(this).apply {
            text = ""
            textSize = 14f
            setTextColor(Color.rgb(94, 98, 109))
        }
        val pinDots = TextView(this).apply {
            text = "____"
            textSize = 32f
            gravity = Gravity.CENTER
            setTextColor(Color.rgb(48, 75, 128))
        }
        val enteredPin = StringBuilder()
        val keypad = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
        }
        val keySize = minOf(
            dp(76),
            (resources.displayMetrics.widthPixels - dp(64)) / 3,
        )

        fun updatePinDots() {
            pinDots.text = (0 until 4).joinToString("  ") { index ->
                if (index < enteredPin.length) "●" else "○"
            }
        }

        fun unlock() {
            if (enteredPin.length != 4) return
            val pin = enteredPin.toString()
            enteredPin.clear()
            updatePinDots()
            if (AppLockStorage.lockoutRemainingMillis(this) > 0L) {
                subtitle.text = "Too many incorrect attempts. Try again later."
            } else if (AppLockStorage.isPinValid(this, pin)) {
                AppLockStorage.clearFailedPinAttempts(this)
                AppLockStorage.unlock(this, targetPackage)
                removeLockWindow()
            } else {
                val remaining = AppLockStorage.recordFailedPinAttempt(this)
                subtitle.text = if (remaining > 0L) {
                    "Too many incorrect attempts. Try again in 30 seconds."
                } else {
                    "Incorrect PIN"
                }
            }
        }

        fun addKey(label: String, onClick: () -> Unit): TextView =
            TextView(this).apply {
                text = label
                textSize = 29f
                gravity = Gravity.CENTER
                setTextColor(Color.rgb(59, 62, 74))
                typeface = Typeface.create("sans-serif", Typeface.NORMAL)
                background = android.graphics.drawable.GradientDrawable().apply {
                    shape = android.graphics.drawable.GradientDrawable.OVAL
                    setColor(Color.rgb(250, 248, 255))
                }
                isClickable = true
                isFocusable = true
                setOnClickListener {
                    if (AppLockStorage.isHapticEnabled(this@UsageStatsLockService)) {
                        performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                    }
                    onClick()
                }
            }

        listOf(
            listOf("1", "2", "3"),
            listOf("4", "5", "6"),
            listOf("7", "8", "9"),
        ).forEach { labels ->
            val row = LinearLayout(this).apply { gravity = Gravity.CENTER }
            labels.forEach { label ->
                val key = addKey(label) {
                    if (AppLockStorage.lockoutRemainingMillis(this) == 0L) {
                        subtitle.text = ""
                        enteredPin.append(label)
                        updatePinDots()
                        if (enteredPin.length == 4) unlock()
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

        val lastRow = LinearLayout(this).apply { gravity = Gravity.CENTER }
        val deleteKey = addKey("⌫") {
            if (enteredPin.isNotEmpty()) enteredPin.deleteCharAt(enteredPin.lastIndex)
            updatePinDots()
        }
        val zeroKey = addKey("0") {
            if (AppLockStorage.lockoutRemainingMillis(this) == 0L) {
                enteredPin.append('0')
                updatePinDots()
                if (enteredPin.length == 4) unlock()
            }
        }
        val submitKey = addKey("›", ::unlock)
        listOf(deleteKey, zeroKey, submitKey).forEach { key ->
            lastRow.addView(
                key,
                LinearLayout.LayoutParams(keySize, keySize).apply {
                    setMargins(dp(4), dp(4), dp(4), dp(4))
                },
            )
        }
        keypad.addView(lastRow)

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
                topMargin = dp(101)
            },
        )
        root.addView(
            pinDots,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.TOP,
            ).apply { topMargin = dp(165) },
        )
        if (AppLockStorage.isBiometricEnabled(this)) {
            val biometricButton = TextView(this).apply {
                text = "Use fingerprint or face unlock"
                textSize = 15f
                gravity = Gravity.CENTER
                setTextColor(Color.rgb(48, 75, 128))
                setOnClickListener {
                    val intent = Intent(
                        this@UsageStatsLockService,
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
            keypad,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
                Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL,
            ).apply { bottomMargin = dp(28) },
        )

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                WindowManager.LayoutParams.FLAG_LAYOUT_INSET_DECOR or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }
        val manager = getSystemService(WINDOW_SERVICE) as WindowManager
        manager.addView(root, params)
        window = root
        lockedPackage = targetPackage
    }

    private fun removeLockWindow() {
        val current = window ?: return
        window = null
        lockedPackage = null
        (getSystemService(WINDOW_SERVICE) as? WindowManager)?.removeView(current)
    }

    private fun buildNotification(): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("App Lock is active")
            .setContentText("Monitoring selected apps using Usage Access")
            .setContentIntent(openApp)
            .setOngoing(true)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                NOTIFICATION_CHANNEL,
                "App Lock monitoring",
                NotificationManager.IMPORTANCE_LOW,
            )
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun dp(value: Int): Int =
        (value * resources.displayMetrics.density).toInt()

    companion object {
        @Volatile
        var isRunning = false
            private set

        private const val NOTIFICATION_CHANNEL = "app_lock_usage_monitor"
        private const val NOTIFICATION_ID = 5101
        private const val POLL_INTERVAL_MS = 350L
        private const val INITIAL_LOOKBACK_MS = 60_000L
    }
}
