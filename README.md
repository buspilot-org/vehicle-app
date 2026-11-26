# Buspilot vehicle app

Android app that runs on a phone in the bus. It is part of [Buspilot](https://buspilot.org), a bus tracking service for privately operated buses (schools, kindergartens, driving schools, hotel shuttles, sports clubs).

What it does (planned):

- Sends the bus position to a [Traccar](https://www.traccar.org) server with the [Traccar Client SDK](https://www.traccar.org/traccar-client-sdk-flutter/), also while the screen is off. GPS pauses while the bus is parked.
- Sends tag sightings and device health to the Buspilot engine as vehicle events (the SDK cannot attach extra data to positions).
- Starts and ends trips automatically from the schedule, so nobody in the bus has to press a button.
- Records a route by driving it once.
- Scans Bluetooth (BLE) tags carried by passengers for the boarding check.
- Reports battery level, temperature and health, so the operator is warned before the phone fails.
- Runs as the only app on a dedicated phone (kiosk mode).

Android only: iOS restricts background Bluetooth scanning, which the boarding check needs.

## Development

```bash
flutter pub get
flutter run
```

## Code layout

| Folder | Content |
|---|---|
| `lib/src/tracking/` | Starts and stops the Traccar Client SDK (positions) and the background service (tags, health, events); permission flow |
| `lib/src/events/` | Vehicle events to the Buspilot engine: event format, offline queue, batch upload |
| `lib/src/ble/` | Bluetooth tag scanning |
| `lib/src/device/` | Battery and device health, start on boot, kiosk mode |
| `lib/src/config/` | Settings (Traccar, positions, engine, tag IDs) |
| `packages/buspilot_ble_scanner/` | Native BLE scanner plugin |
| `packages/buspilot_battery/` | Native battery reader plugin (works in the background service too) |

### What runs in the background

While tracking is on, two foreground services run in the app's process:

1. The Traccar Client SDK's own service sends positions to Traccar. It pauses
   GPS while the bus is parked (activity recognition and a geofence), buffers
   positions in SQLite while offline and restarts after a reboot. The app sees
   no positions, only the SDK's log.
2. The app's own service (`lib/src/tracking/companion_task_handler.dart`,
   flutter_foreground_task) runs tag scanning, device health and the event
   upload in a Flutter engine of its own, so it works without the UI and also
   restarts after a reboot.

Both post the same notification ID, so the phone shows one notification. The
SDK holds a wake lock only while the bus moves; the app's service holds none,
so the phone can sleep while parked.

## Contributing

Every pull request gets at least one thorough self-review before merge. The organisation has no automatic review bot.

## License

[GNU Affero General Public License v3.0](LICENSE)

The Buspilot name, logo, launcher icons and brand colours (`lib/src/ui/brand/`, the launcher icons under `android/app/src/main/res/mipmap-*`) come from the private `buspilot-org/brand` repository and are not covered by this licence. All rights reserved; forks must replace them. The M PLUS Rounded 1c font in `assets/fonts/` is licensed under the [SIL Open Font License 1.1](assets/fonts/OFL.txt).
