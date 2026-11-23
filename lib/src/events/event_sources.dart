import '../ble/presence_tracker.dart';
import '../ble/tag_filter.dart';
import '../device/battery_snapshot.dart';
import '../device/device_warnings.dart';
import 'vehicle_event.dart';

/// The event for a presence change, or null if the tag is not one of the
/// operator's tags ([filter]).
///
/// `tag_seen` carries the time and RSSI of the first sighting. `tag_gone`
/// carries the time the tag was last heard, not the time its absence was
/// noticed (that is [PresenceConfig.absentAfter] later, when the bus may have
/// left the stop already).
VehicleEvent? tagEventFor(PresenceEvent event, TagFilter filter) {
  if (filter.isEmpty || !filter.matches(event.tag.beacon)) return null;
  return switch (event) {
    TagEntered(:final tag, :final time) => VehicleEvent.tagSeen(
      tagId: tag.tagId,
      rssi: tag.rssi,
      time: time,
    ),
    TagLeft(:final tag) => VehicleEvent.tagGone(
      tagId: tag.tagId,
      time: tag.lastSeen,
    ),
  };
}

/// `tags_on_board` for the tags of the operator that are still present.
VehicleEvent tagsOnBoardEvent(
  Iterable<PresentTag> present,
  TagFilter filter,
  DateTime time,
) => VehicleEvent.tagsOnBoard(
  tagIds: [
    for (final tag in present)
      if (!filter.isEmpty && filter.matches(tag.beacon)) tag.tagId,
  ],
  time: time,
);

/// Decides when a battery reading becomes a `device_health` event: every
/// [interval], and at once when a warning appears that was not there in the
/// previous reading.
class HealthEventScheduler {
  HealthEventScheduler({
    this.interval = const Duration(minutes: 5),
    this.tolerance = const Duration(seconds: 5),
  });

  final Duration interval;

  /// Readings come from a periodic poll; a reading this much earlier than
  /// [interval] still counts as due, so the poll's jitter does not push the
  /// event to the next poll.
  final Duration tolerance;

  DateTime? _lastEmitted;
  Set<String> _lastCodes = const {};

  /// Returns the event to record for this reading, or null.
  VehicleEvent? onReading(
    BatterySnapshot? battery,
    List<DeviceWarning> warnings,
  ) {
    if (battery == null) return null;
    final codes = {for (final w in warnings) w.code};
    final newWarning = codes.difference(_lastCodes).isNotEmpty;
    _lastCodes = codes;
    final last = _lastEmitted;
    final due =
        last == null ||
        battery.timestamp.difference(last) >= interval - tolerance ||
        battery.timestamp.isBefore(last); // phone clock changed
    if (!due && !newWarning) return null;
    _lastEmitted = battery.timestamp;
    return VehicleEvent.deviceHealth(battery: battery, warnings: warnings);
  }
}
