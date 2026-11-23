# Buspilot vehicle app

Android app that runs on a phone in the bus. It is part of [Buspilot](https://buspilot.org), a bus tracking service for privately operated buses (schools, kindergartens, driving schools, hotel shuttles, sports clubs).

What it does (planned):

- Sends the bus position to a [Traccar](https://www.traccar.org) server (OsmAnd protocol), also while the screen is off.
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
| `lib/src/tracking/` | Location service and sending positions to Traccar |
| `lib/src/ble/` | Bluetooth tag scanning |
| `lib/src/device/` | Battery and device health, start on boot, kiosk mode |
| `lib/src/config/` | Settings (server URL, device ID) |

## Contributing

Every pull request gets at least one thorough self-review before merge. The organisation has no automatic review bot.

## License

[GNU Affero General Public License v3.0](LICENSE)
