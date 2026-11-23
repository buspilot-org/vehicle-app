package org.buspilot.buspilot_vehicle.device

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Platform channel for lib/src/device/device_channel.dart. */
object DeviceChannel {
    const val NAME = "org.buspilot.vehicle/device"

    fun register(engine: FlutterEngine, activity: Activity) {
        MethodChannel(engine.dartExecutor.binaryMessenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBattery" -> result.success(BatteryReader.read(activity))
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
