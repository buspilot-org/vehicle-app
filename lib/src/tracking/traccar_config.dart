import 'package:traccar_client_sdk/traccar_client_sdk.dart' as sdk;

import '../config/tracking_config.dart';

/// Text of the persistent notification. The SDK's service and our own
/// background service share one notification (see `TrackingController`), so
/// both use the same text.
const trackingNotificationText = 'Tracking is on';

/// Radius around the parked position; leaving it resumes GPS (SDK default).
const stationaryRadiusMeters = 100;

/// Maps the app settings to the Traccar Client SDK configuration.
///
/// Fixed choices (not in the settings):
/// - `buffer: true`: positions are stored in the SDK's SQLite queue and
///   retried, so nothing is lost while offline.
/// - `wakeLock: true`: the SDK holds a partial wake lock only while tracking
///   and moving (released while stop detection has paused GPS). It keeps the
///   CPU awake for our background service too, so tag and health events are
///   on time while driving, and lets the phone sleep while parked.
/// - Fused location provider when Google Play services are present.
sdk.Config toTraccarConfig(TrackingConfig c) => sdk.Config(
  serverUrl: c.serverUrl.trim(),
  deviceId: c.deviceId,
  location: sdk.LocationConfig(
    accuracy: switch (c.accuracy) {
      TrackingAccuracy.highest => sdk.Accuracy.highest,
      TrackingAccuracy.high => sdk.Accuracy.high,
      TrackingAccuracy.medium => sdk.Accuracy.medium,
      TrackingAccuracy.low => sdk.Accuracy.low,
    },
    distanceMeters: c.distanceFilterMeters,
    intervalSeconds: c.intervalSeconds,
    angleDegrees: 0,
    stopDetection: c.stopDetection,
    stopTimeoutSeconds: c.stopTimeoutSeconds,
    stationaryRadiusMeters: stationaryRadiusMeters,
    heartbeatIntervalSeconds: c.stopDetection ? c.heartbeatSeconds : 0,
  ),
  wakeLock: true,
  buffer: true,
  preferPlatformProviders: false,
  notification: const sdk.NotificationConfig(text: trackingNotificationText),
);
