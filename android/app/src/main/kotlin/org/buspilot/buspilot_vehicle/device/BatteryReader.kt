package org.buspilot.buspilot_vehicle.device

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build

/**
 * Reads the sticky ACTION_BATTERY_CHANGED broadcast. Passing a null receiver
 * returns the last broadcast without registering anything, so this is cheap
 * enough to call on every poll.
 */
object BatteryReader {
    // BatteryManager.EXTRA_CYCLE_COUNT, public since API 34.
    private const val EXTRA_CYCLE_COUNT = "android.os.extra.CYCLE_COUNT"

    fun read(context: Context): Map<String, Any?> {
        val intent: Intent = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED),
        ) ?: return mapOf("available" to false)

        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        // Floor, so "100" only means really full (99.5 % must not count).
        val percent = if (level >= 0 && scale > 0) level * 100 / scale else null

        val temperatureTenths = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        val voltage = intent.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)
        val cycleCount = if (Build.VERSION.SDK_INT >= 34) {
            intent.getIntExtra(EXTRA_CYCLE_COUNT, -1)
        } else {
            -1
        }

        return mapOf(
            "available" to true,
            "level" to percent,
            "status" to statusName(intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)),
            "plugged" to pluggedName(intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)),
            "health" to healthName(intent.getIntExtra(BatteryManager.EXTRA_HEALTH, -1)),
            "temperatureC" to if (temperatureTenths == Int.MIN_VALUE) null else temperatureTenths / 10.0,
            "voltageMv" to if (voltage > 0) voltage else null,
            "cycleCount" to if (cycleCount >= 0) cycleCount else null,
        )
    }

    private fun statusName(value: Int): String = when (value) {
        BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
        BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
        BatteryManager.BATTERY_STATUS_FULL -> "full"
        BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "notCharging"
        else -> "unknown"
    }

    private fun pluggedName(value: Int): String = when (value) {
        0 -> "none"
        BatteryManager.BATTERY_PLUGGED_AC -> "ac"
        BatteryManager.BATTERY_PLUGGED_USB -> "usb"
        BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
        8 -> "dock" // BatteryManager.BATTERY_PLUGGED_DOCK, API 33
        else -> "unknown"
    }

    private fun healthName(value: Int): String = when (value) {
        BatteryManager.BATTERY_HEALTH_GOOD -> "good"
        BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
        BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
        BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "overVoltage"
        BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "failure"
        BatteryManager.BATTERY_HEALTH_COLD -> "cold"
        else -> "unknown"
    }
}
