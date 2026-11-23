# buspilot_battery

Reads Android's sticky `ACTION_BATTERY_CHANGED` broadcast (level, charge status,
power source, health, temperature, voltage, cycle count).

It is a plugin rather than a channel registered in `MainActivity`, because
plugins are registered in every Flutter engine, including the one the
background service (`flutter_foreground_task`) starts. The app parses the map
in `lib/src/device/battery_snapshot.dart`.
