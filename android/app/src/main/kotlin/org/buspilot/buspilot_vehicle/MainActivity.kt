package org.buspilot.buspilot_vehicle

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import org.buspilot.buspilot_vehicle.device.DeviceChannel
import org.buspilot.buspilot_vehicle.device.KioskController

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        DeviceChannel.register(flutterEngine, this)
    }

    override fun onResume() {
        super.onResume()
        KioskController.onActivityResumed(this)
    }
}
