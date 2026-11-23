package org.buspilot.buspilot_vehicle.device

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.os.Build
import android.util.Log

/**
 * Lock task ("kiosk") handling.
 *
 * - Device owner: the app allow-lists itself for lock task, so startLockTask()
 *   locks the phone to the app without a prompt. Kiosk is on by default and is
 *   re-entered on every resume (also after a reboot) until someone turns it off
 *   on the status screen.
 * - Not device owner: startLockTask() falls back to screen pinning, which the
 *   user has to confirm. It is only started from the status screen.
 */
object KioskController {
    private const val TAG = "BuspilotKiosk"
    private const val PREFS = "buspilot_device"
    private const val KEY_KIOSK_ENABLED = "kiosk_enabled"

    fun isDeviceOwner(context: Context): Boolean {
        val dpm = context.getSystemService(DevicePolicyManager::class.java) ?: return false
        return dpm.isDeviceOwnerApp(context.packageName)
    }

    /** "none", "pinned" (screen pinning) or "locked" (device-owner lock task). */
    fun lockTaskState(context: Context): String {
        val am = context.getSystemService(ActivityManager::class.java) ?: return "none"
        return when (am.lockTaskModeState) {
            ActivityManager.LOCK_TASK_MODE_LOCKED -> "locked"
            ActivityManager.LOCK_TASK_MODE_PINNED -> "pinned"
            else -> "none"
        }
    }

    fun isKioskEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_KIOSK_ENABLED, true)

    private fun setKioskEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_KIOSK_ENABLED, enabled).apply()
    }

    /** Called from MainActivity.onResume(). */
    fun onActivityResumed(activity: Activity) {
        if (!isDeviceOwner(activity)) return
        configureDeviceOwnerLockTask(activity)
        if (isKioskEnabled(activity) && lockTaskState(activity) == "none") {
            startLockTask(activity)
        }
    }

    /** Enters lock task (device owner) or asks for screen pinning (otherwise). */
    fun enter(activity: Activity) {
        setKioskEnabled(activity, true)
        if (isDeviceOwner(activity)) configureDeviceOwnerLockTask(activity)
        startLockTask(activity)
    }

    fun exit(activity: Activity) {
        setKioskEnabled(activity, false)
        try {
            activity.stopLockTask()
        } catch (e: RuntimeException) {
            Log.w(TAG, "stopLockTask failed", e)
        }
    }

    private fun startLockTask(activity: Activity) {
        try {
            activity.startLockTask()
        } catch (e: RuntimeException) {
            // Thrown e.g. when the activity is not in the foreground yet.
            Log.w(TAG, "startLockTask failed", e)
        }
    }

    private fun configureDeviceOwnerLockTask(context: Context) {
        val dpm = context.getSystemService(DevicePolicyManager::class.java) ?: return
        val admin = BuspilotDeviceAdminReceiver.component(context)
        try {
            dpm.setLockTaskPackages(admin, arrayOf(context.packageName))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                // Keep the power menu so the phone can still be restarted, and
                // the status bar info (clock, battery) for the driver.
                dpm.setLockTaskFeatures(
                    admin,
                    DevicePolicyManager.LOCK_TASK_FEATURE_GLOBAL_ACTIONS or
                        DevicePolicyManager.LOCK_TASK_FEATURE_SYSTEM_INFO,
                )
            }
        } catch (e: SecurityException) {
            Log.w(TAG, "Could not configure lock task as device owner", e)
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
