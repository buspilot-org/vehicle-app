# buspilot_ble_scanner

Small Android-only Flutter plugin used by the Buspilot vehicle app
(`lib/src/ble/`). It starts a BLE scan with hardware scan filters for
iBeacon (Apple manufacturer data `02 15`) and Eddystone-UID (service data
`0xFEAA`, frame type `0x00`), optionally narrowed to given iBeacon UUIDs and
Eddystone namespaces, and streams every result to Dart as
`{address, rssi, bytes}`, where `bytes` is the raw advertisement
(`ScanRecord.getBytes()`). All parsing happens in Dart.

Why a local plugin instead of a pub.dev package:

- Android pauses **unfiltered** scans while the screen is off (8.1+) and
  downgrades long unfiltered scans; filtered scans keep running, which the
  boarding check needs.
- `flutter_blue_plus` is no longer under an open-source licence, and
  `flutter_reactive_ble` cannot set manufacturer-data or service-data filters.

Licensed under AGPL-3.0, like the app (see `../../LICENSE`).
