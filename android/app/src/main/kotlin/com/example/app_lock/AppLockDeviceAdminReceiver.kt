package com.example.app_lock

import android.app.admin.DeviceAdminReceiver
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.Toast

class AppLockDeviceAdminReceiver : DeviceAdminReceiver() {
    override fun onDisableRequested(context: Context, intent: Intent): CharSequence =
        "Disabling this protection will allow App Lock to be uninstalled."

    override fun onDisabled(context: Context, intent: Intent) {
        Toast.makeText(context, "Anti-uninstall protection is off.", Toast.LENGTH_SHORT)
            .show()
    }

    companion object {
        fun component(context: Context) =
            ComponentName(context, AppLockDeviceAdminReceiver::class.java)

        fun isActive(context: Context): Boolean {
            val manager =
                context.getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            return manager.isAdminActive(component(context))
        }
    }
}
