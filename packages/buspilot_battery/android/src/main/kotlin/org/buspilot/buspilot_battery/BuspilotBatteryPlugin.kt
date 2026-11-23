// SPDX-License-Identifier: AGPL-3.0-or-later
package org.buspilot.buspilot_battery

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/** Serves `getBattery` on `org.buspilot.vehicle/battery` in every engine. */
class BuspilotBatteryPlugin : FlutterPlugin {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context: Context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "org.buspilot.vehicle/battery").also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBattery" -> result.success(BatteryReader.read(context))
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
