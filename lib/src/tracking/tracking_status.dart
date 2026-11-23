import 'position_record.dart';

/// Snapshot of the tracking service, sent from the service isolate to the UI.
class TrackingStatus {
  const TrackingStatus({
    this.lastSent,
    this.lastSentAt,
    this.lastFixAt,
    this.queueLength = 0,
    this.droppedCount = 0,
    this.error,
  });

  /// Last position Traccar confirmed.
  final PositionRecord? lastSent;

  /// When [lastSent] was confirmed (phone clock).
  final DateTime? lastSentAt;

  /// When the last location fix arrived from Android.
  final DateTime? lastFixAt;

  /// Positions waiting to be sent.
  final int queueLength;

  /// Positions dropped because the offline queue was full.
  final int droppedCount;

  /// Current problem, if any (no network, server error, location off, ...).
  final String? error;

  static const messageType = 'trackingStatus';

  Map<String, Object?> toMessage() => {
    'type': messageType,
    if (lastSent != null) 'lastSent': lastSent!.toJson(),
    if (lastSentAt != null) 'lastSentAt': lastSentAt!.millisecondsSinceEpoch,
    if (lastFixAt != null) 'lastFixAt': lastFixAt!.millisecondsSinceEpoch,
    'queueLength': queueLength,
    'droppedCount': droppedCount,
    if (error != null) 'error': error,
  };

  /// Returns null if [data] is not a status message.
  static TrackingStatus? fromMessage(Object? data) {
    if (data is! Map || data['type'] != messageType) return null;
    DateTime? time(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    final lastSent = data['lastSent'];
    return TrackingStatus(
      lastSent: lastSent is Map
          ? PositionRecord.fromJson(_deepCast(lastSent))
          : null,
      lastSentAt: time(data['lastSentAt']),
      lastFixAt: time(data['lastFixAt']),
      queueLength: data['queueLength'] as int? ?? 0,
      droppedCount: data['droppedCount'] as int? ?? 0,
      error: data['error'] as String?,
    );
  }
}

/// Messages from isolates arrive as `Map<Object?, Object?>`; convert nested
/// maps to `Map<String, Object?>`.
Map<String, Object?> _deepCast(Map<Object?, Object?> map) =>
    map.map((k, v) => MapEntry(k! as String, v is Map ? _deepCast(v) : v));
