import 'dart:math';

import 'package:flutter/foundation.dart';

import '../device/battery_snapshot.dart';
import '../device/device_warnings.dart';

/// Event types of the vehicle event channel (internal concept,
/// `server.md` › "Vehicle events").
abstract final class VehicleEventType {
  static const tagSeen = 'tag_seen';
  static const tagGone = 'tag_gone';
  static const tagsOnBoard = 'tags_on_board';
  static const deviceHealth = 'device_health';
}

/// One event for `POST {engineUrl}/v1/vehicle-events`.
///
/// Stored in the phone's event queue exactly in its wire format ([toJson]),
/// so a queued event is sent unchanged however often it is retried. The
/// engine ignores duplicate [id]s.
///
/// Privacy: tag events carry only the tag ID (and RSSI), never names, MAC
/// addresses or positions.
@immutable
class VehicleEvent {
  const VehicleEvent._(this.id, this.type, this.time, this.payload);

  /// A tag of the operator was heard for the first time.
  factory VehicleEvent.tagSeen({
    required String tagId,
    required int rssi,
    required DateTime time,
    String? id,
  }) => VehicleEvent._(id ?? newEventId(), VehicleEventType.tagSeen, time, {
    'tag': {'id': tagId, 'rssi': rssi},
  });

  /// A tag was not heard any more. [time] should be when it was last heard.
  factory VehicleEvent.tagGone({
    required String tagId,
    required DateTime time,
    String? id,
  }) => VehicleEvent._(id ?? newEventId(), VehicleEventType.tagGone, time, {
    'tag': {'id': tagId},
  });

  /// Tags still present when tracking stopped (can be empty).
  factory VehicleEvent.tagsOnBoard({
    required List<String> tagIds,
    required DateTime time,
    String? id,
  }) => VehicleEvent._(id ?? newEventId(), VehicleEventType.tagsOnBoard, time, {
    'tags': List<String>.unmodifiable(tagIds),
  });

  /// Battery state and the current warning codes.
  factory VehicleEvent.deviceHealth({
    required BatterySnapshot battery,
    required List<DeviceWarning> warnings,
    String? id,
  }) => VehicleEvent._(
    id ?? newEventId(),
    VehicleEventType.deviceHealth,
    battery.timestamp,
    {
      'battery': {
        'level': ?battery.level,
        'charging': battery.status == BatteryChargeStatus.charging,
        'source': battery.source.name,
        'temperatureC': ?battery.temperatureC,
        'health': battery.health.name,
      },
      'warnings': [for (final w in warnings) w.code],
    },
  );

  /// Reads an event back from the queue file. Throws [FormatException] or
  /// [TypeError] for a damaged line.
  factory VehicleEvent.fromJson(Map<String, Object?> json) {
    final id = json['id']! as String;
    final type = json['type']! as String;
    final time = DateTime.parse(json['time']! as String);
    if (id.isEmpty || type.isEmpty) {
      throw const FormatException('Event without id or type');
    }
    final payload = Map<String, Object?>.of(json)
      ..remove('id')
      ..remove('type')
      ..remove('time');
    return VehicleEvent._(id, type, time, Map.unmodifiable(payload));
  }

  /// Client-generated UUID (version 4).
  final String id;
  final String type;
  final DateTime time;

  /// The type-specific fields (`tag`, `tags`, `battery`, `warnings`).
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'time': formatEventTime(time),
    ...payload,
  };

  @override
  String toString() => 'VehicleEvent($type $id at ${formatEventTime(time)})';
}

/// The request body for a batch of events.
Map<String, Object?> vehicleEventBatch(
  String deviceId,
  List<VehicleEvent> events,
) => {
  'deviceId': deviceId,
  'events': [for (final e in events) e.toJson()],
};

/// UTC with second precision, e.g. `2026-11-23T10:30:01Z`.
String formatEventTime(DateTime time) {
  final t = time.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}-${two(t.month)}-${two(t.day)}'
      'T${two(t.hour)}:${two(t.minute)}:${two(t.second)}Z';
}

final Random _random = Random.secure();

/// A random (version 4) UUID, lowercase with dashes.
String newEventId([Random? random]) {
  final rng = random ?? _random;
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // RFC 4122 variant
  final hex = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
