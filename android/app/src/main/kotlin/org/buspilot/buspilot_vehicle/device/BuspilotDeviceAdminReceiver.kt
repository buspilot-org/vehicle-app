package org.buspilot.buspilot_vehicle.device

import android.app.admin.DeviceAdminReceiver
import android.content.ComponentName
import android.content.Context

/**
 * Device admin component. It does nothing by itself; it exists so the app can
 * be provisioned as device owner (`adb shell dpm set-device-owner ...`), which
 * allows lock task mode without user confirmation and starting the activity
 * from the boot receiver. See docs/dedicated-phone.md.
 */
class BuspilotDeviceAdminReceiver : DeviceAdminReceiver() {
    companion object {
        fun component(context: Context): ComponentName =
            ComponentName(context.applicationContext, BuspilotDeviceAdminReceiver::class.java)
    }
}
