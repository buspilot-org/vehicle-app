package org.buspilot.buspilot_vehicle.device

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel for lib/src/device/device_channel.dart. Registered on the
 * activity's engine only; the battery reading lives in packages/buspilot_battery
 * so the background service can use it too.
 */
object DeviceChannel {
    const val NAME = "org.buspilot.vehicle/device"

    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDeviceState" -> result.success(deviceState(activity))
                "enterKiosk" -> {
                    KioskController.enter(activity)
                    result.success(null)
                }
                "exitKiosk" -> {
                    KioskController.exit(activity)
                    result.success(null)
                }
                "openBatteryOptimizationSettings" -> {
                    // Lock task mode silently blocks other apps' activities.
                    if (KioskController.lockTaskState(activity) != "none") {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        activity.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
                        result.success(true)
                    } catch (e: RuntimeException) {
                        // No such settings screen on this phone.
                        result.success(false)
                    }
                }
                "deleteNotificationChannel" -> {
                    val id = call.argument<String>("id")
                    if (id != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        activity.getSystemService(NotificationManager::class.java)
                            ?.deleteNotificationChannel(id)
                    }
                    result.success(null)
                }
                "openLocationSettings" -> {
                    if (KioskController.lockTaskState(activity) != "none") {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    try {
                        activity.startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
                        result.success(true)
                    } catch (e: RuntimeException) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun deviceState(context: Context): Map<String, Any?> {
        val pm = context.getSystemService(PowerManager::class.java)
        return mapOf(
            "deviceOwner" to KioskController.isDeviceOwner(context),
            "lockTaskState" to KioskController.lockTaskState(context),
            "kioskEnabled" to KioskController.isKioskEnabled(context),
            "ignoringBatteryOptimizations" to (pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false),
        )
    }
}
