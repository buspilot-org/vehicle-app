package org.buspilot.buspilot_vehicle.device

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import org.buspilot.buspilot_vehicle.MainActivity

/**
 * Starts the app after the phone boots (or after the app was updated), so a
 * dedicated phone in a bus recovers from a restart without anyone touching it.
 *
 * Android 10+ blocks activity starts from the background. The start is allowed
 * when the app is device owner (the recommended setup, see
 * docs/dedicated-phone.md) or has the "display over other apps" permission;
 * otherwise Android ignores it and the app has to be opened by hand.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            ACTION_QUICKBOOT_POWERON -> launch(context)
        }
    }

    private fun launch(context: Context) {
        val launch = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        try {
            context.startActivity(launch)
        } catch (e: RuntimeException) {
            Log.w("BuspilotBoot", "Could not start MainActivity after boot", e)
        }
    }

    companion object {
        // Sent instead of BOOT_COMPLETED by some vendors' fast boot.
        private const val ACTION_QUICKBOOT_POWERON = "android.intent.action.QUICKBOOT_POWERON"
    }
}
