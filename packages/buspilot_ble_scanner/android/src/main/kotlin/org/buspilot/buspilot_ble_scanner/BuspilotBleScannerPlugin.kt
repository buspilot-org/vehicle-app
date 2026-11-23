// SPDX-License-Identifier: AGPL-3.0-or-later
package org.buspilot.buspilot_ble_scanner

import android.annotation.SuppressLint
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Streams BLE advertisements matching iBeacon / Eddystone-UID hardware filters.
 *
 * Filtered scans keep running while the screen is off; unfiltered ones are paused by
 * Android 8.1+. Parsing of the advertisement bytes is done in Dart.
 */
class BuspilotBleScannerPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var scanner: BluetoothLeScanner? = null
    private var callback: ScanCallback? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, "org.buspilot/ble_scanner")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "org.buspilot/ble_scanner/scan")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopScan()
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isBluetoothEnabled" -> result.success(adapter()?.isEnabled == true)
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stopScan()
        sink = events
        val args = arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        val adapter = adapter()
        if (adapter == null || !adapter.isEnabled) {
            events.error("bluetooth_off", "Bluetooth is not available or switched off", null)
            return
        }
        val leScanner = adapter.bluetoothLeScanner
        if (leScanner == null) {
            events.error("bluetooth_off", "BLE scanner not available", null)
            return
        }
        val filters = try {
            buildFilters(args)
        } catch (e: IllegalArgumentException) {
            events.error("invalid_filter", e.message, null)
            return
        }
        if (filters.isEmpty()) {
            events.error("invalid_filter", "No beacon format selected", null)
            return
        }
        val settings = ScanSettings.Builder()
            .setScanMode(scanMode(args["scanMode"] as? String))
            .setCallbackType(ScanSettings.CALLBACK_TYPE_ALL_MATCHES)
            .setReportDelay(0)
            .build()
        val cb = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) = emit(result)

            override fun onBatchScanResults(results: MutableList<ScanResult>) =
                results.forEach { emit(it) }

            override fun onScanFailed(errorCode: Int) {
                mainHandler.post {
                    sink?.error("scan_failed", "BLE scan failed with code $errorCode", errorCode)
                }
            }
        }
        try {
            startScan(leScanner, filters, settings, cb)
            scanner = leScanner
            callback = cb
        } catch (e: SecurityException) {
            events.error("permission_denied", e.message, null)
        }
    }

    override fun onCancel(arguments: Any?) {
        stopScan()
    }

    private fun emit(result: ScanResult) {
        val bytes = result.scanRecord?.bytes ?: return
        val event = mapOf(
            "address" to result.device.address,
            "rssi" to result.rssi,
            "bytes" to bytes,
        )
        mainHandler.post { sink?.success(event) }
    }

    @SuppressLint("MissingPermission") // Checked in Dart; SecurityException is caught.
    private fun startScan(
        leScanner: BluetoothLeScanner,
        filters: List<ScanFilter>,
        settings: ScanSettings,
        cb: ScanCallback,
    ) = leScanner.startScan(filters, settings, cb)

    @SuppressLint("MissingPermission")
    private fun stopScan() {
        val cb = callback
        val leScanner = scanner
        callback = null
        scanner = null
        sink = null
        if (cb != null && leScanner != null) {
            try {
                // Throws if the adapter was switched off meanwhile; nothing to stop then.
                leScanner.stopScan(cb)
            } catch (ignored: Exception) {
            }
        }
    }

    private fun adapter() =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun scanMode(name: String?) = when (name) {
        "lowPower" -> ScanSettings.SCAN_MODE_LOW_POWER
        "balanced" -> ScanSettings.SCAN_MODE_BALANCED
        else -> ScanSettings.SCAN_MODE_LOW_LATENCY
    }

    private fun buildFilters(args: Map<*, *>): List<ScanFilter> {
        val filters = mutableListOf<ScanFilter>()
        if (args["includeIBeacon"] as? Boolean != false) {
            val uuids = (args["iBeaconUuids"] as? List<*>).orEmpty().map { hex(it as String, 16) }
            if (uuids.isEmpty()) {
                filters += iBeaconFilter(null)
            } else {
                uuids.forEach { filters += iBeaconFilter(it) }
            }
        }
        if (args["includeEddystone"] as? Boolean != false) {
            val namespaces =
                (args["eddystoneNamespaces"] as? List<*>).orEmpty().map { hex(it as String, 10) }
            if (namespaces.isEmpty()) {
                filters += eddystoneUidFilter(null)
            } else {
                namespaces.forEach { filters += eddystoneUidFilter(it) }
            }
        }
        return filters
    }

    /** Apple company ID 0x004C, payload `02 15 <uuid>`; partial data matches as a prefix. */
    private fun iBeaconFilter(uuid: ByteArray?): ScanFilter {
        val data = byteArrayOf(0x02, 0x15) + (uuid ?: ByteArray(0))
        val mask = ByteArray(data.size) { 0xFF.toByte() }
        return ScanFilter.Builder().setManufacturerData(APPLE_COMPANY_ID, data, mask).build()
    }

    /** Service data for 0xFEAA: frame type 0x00 (UID), tx power (ignored), namespace. */
    private fun eddystoneUidFilter(namespace: ByteArray?): ScanFilter {
        val data: ByteArray
        val mask: ByteArray
        if (namespace == null) {
            data = byteArrayOf(0x00)
            mask = byteArrayOf(0xFF.toByte())
        } else {
            data = byteArrayOf(0x00, 0x00) + namespace
            mask = byteArrayOf(0xFF.toByte(), 0x00) + ByteArray(namespace.size) { 0xFF.toByte() }
        }
        return ScanFilter.Builder().setServiceData(EDDYSTONE_UUID, data, mask).build()
    }

    private fun hex(value: String, length: Int): ByteArray {
        val clean = value.replace("-", "")
        require(clean.length == length * 2 && clean.all { it.isDigit() || it.lowercaseChar() in 'a'..'f' }) {
            "Expected $length bytes of hex, got '$value'"
        }
        return ByteArray(length) { clean.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }

    private companion object {
        const val APPLE_COMPANY_ID = 0x004C
        val EDDYSTONE_UUID: ParcelUuid = ParcelUuid.fromString("0000FEAA-0000-1000-8000-00805F9B34FB")
    }
}
