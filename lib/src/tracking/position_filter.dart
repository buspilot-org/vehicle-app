import 'dart:math';

import 'position_record.dart';

/// Decides which location fixes are worth sending.
///
/// - Fixes older than the last accepted one are dropped.
/// - Fixes that arrive sooner than [minInterval] after the last accepted one
///   are dropped (Android sometimes delivers more often than requested).
/// - With a [distanceFilterMeters] above 0, a fix is only accepted once the
///   bus moved that far, or when [stationaryInterval] has passed, so a parked
///   bus still reports now and then and does not show as offline.
class PositionFilter {
  PositionFilter({
    required Duration interval,
    required this.distanceFilterMeters,
    this.stationaryInterval = const Duration(minutes: 5),
  }) : minInterval = interval * 0.8;

  /// Shortest gap between two accepted fixes (80 % of the requested interval,
  /// to allow for jitter in Android's delivery).
  final Duration minInterval;
  final int distanceFilterMeters;
  final Duration stationaryInterval;

  PositionRecord? _last;

  bool accept(PositionRecord position) {
    final last = _last;
    if (last != null) {
      final elapsed = position.timestamp.difference(last.timestamp);
      if (elapsed <= Duration.zero || elapsed < minInterval) return false;
      if (distanceFilterMeters > 0 &&
          elapsed < stationaryInterval &&
          distanceMeters(last, position) < distanceFilterMeters) {
        return false;
      }
    }
    _last = position;
    return true;
  }
}

/// Great-circle distance in metres (haversine formula).
double distanceMeters(PositionRecord a, PositionRecord b) {
  const earthRadius = 6371008.8;
  double rad(double deg) => deg * pi / 180;
  final dLat = rad(b.latitude - a.latitude);
  final dLon = rad(b.longitude - a.longitude);
  final h =
      pow(sin(dLat / 2), 2) +
      cos(rad(a.latitude)) * cos(rad(b.latitude)) * pow(sin(dLon / 2), 2);
  return 2 * earthRadius * asin(sqrt(h));
}
