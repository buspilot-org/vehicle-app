/// Snapshot of the background service (tags, device health, vehicle
/// events), sent from the service isolate to the UI.
class CompanionStatus {
  const CompanionStatus({
    this.engineConfigured = false,
    this.eventQueueLength = 0,
    this.eventsDropped = 0,
    this.eventsSent = 0,
    this.lastEventsSentAt,
    this.nextEventAttempt,
    this.eventError,
    this.tagsConfigured = false,
    this.tagScan,
    this.tagsPresent = 0,
    this.batteryLevel,
    this.warnings = const [],
    this.error,
  });

  /// Whether an engine URL is set (otherwise events are only queued).
  final bool engineConfigured;
  final int eventQueueLength;

  /// Events dropped because the queue was full.
  final int eventsDropped;

  /// Events the engine confirmed since the service started.
  final int eventsSent;
  final DateTime? lastEventsSentAt;

  /// When the uploader retries after a failure.
  final DateTime? nextEventAttempt;
  final String? eventError;

  /// Whether operator tag IDs are configured (otherwise no scanning).
  final bool tagsConfigured;

  /// Scanner state, e.g. `scanning` or `noPermission: ...`.
  final String? tagScan;
  final int tagsPresent;
  final int? batteryLevel;

  /// Current device warning codes.
  final List<String> warnings;

  /// A problem that stops the service from working (settings, queue file).
  final String? error;

  static const messageType = 'companionStatus';

  Map<String, Object?> toMessage() => {
    'type': messageType,
    'engineConfigured': engineConfigured,
    'eventQueueLength': eventQueueLength,
    'eventsDropped': eventsDropped,
    'eventsSent': eventsSent,
    'lastEventsSentAt': ?lastEventsSentAt?.millisecondsSinceEpoch,
    'nextEventAttempt': ?nextEventAttempt?.millisecondsSinceEpoch,
    'eventError': ?eventError,
    'tagsConfigured': tagsConfigured,
    'tagScan': ?tagScan,
    'tagsPresent': tagsPresent,
    'batteryLevel': ?batteryLevel,
    'warnings': warnings,
    'error': ?error,
  };

  /// Returns null if [data] is not a status message.
  static CompanionStatus? fromMessage(Object? data) {
    if (data is! Map || data['type'] != messageType) return null;
    DateTime? time(Object? v) =>
        v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
    return CompanionStatus(
      engineConfigured: data['engineConfigured'] == true,
      eventQueueLength: data['eventQueueLength'] as int? ?? 0,
      eventsDropped: data['eventsDropped'] as int? ?? 0,
      eventsSent: data['eventsSent'] as int? ?? 0,
      lastEventsSentAt: time(data['lastEventsSentAt']),
      nextEventAttempt: time(data['nextEventAttempt']),
      eventError: data['eventError'] as String?,
      tagsConfigured: data['tagsConfigured'] == true,
      tagScan: data['tagScan'] as String?,
      tagsPresent: data['tagsPresent'] as int? ?? 0,
      batteryLevel: data['batteryLevel'] as int?,
      warnings: [
        for (final w in data['warnings'] as List? ?? const []) w as String,
      ],
      error: data['error'] as String?,
    );
  }
}
