import 'package:buspilot_ble_scanner/buspilot_ble_scanner.dart';

import 'beacon.dart';

/// Decides which beacons count as the operator's tags.
///
/// Configured with the operator's iBeacon proximity UUIDs and Eddystone
/// namespaces. The same filter is also pushed down to the Android scanner as
/// hardware scan filters ([toScanFilter]), so other beacons nearby are not even
/// delivered to the app.
///
/// Configure each tag to send a single format: a tag that sends both iBeacon
/// and Eddystone-UID (Teltonika EYE can) has two tag IDs and counts twice.
class TagFilter {
  /// Only beacons with one of these iBeacon UUIDs or Eddystone namespaces.
  /// Invalid entries throw [FormatException]. With both lists empty nothing
  /// matches; use [TagFilter.any] to accept every beacon.
  factory TagFilter({
    Iterable<String> iBeaconUuids = const [],
    Iterable<String> eddystoneNamespaces = const [],
  }) {
    return TagFilter._(
      iBeaconUuids: {for (final u in iBeaconUuids) _uuid(u)},
      eddystoneNamespaces: {for (final n in eddystoneNamespaces) _namespace(n)},
      acceptAll: false,
    );
  }

  /// Accepts every iBeacon and Eddystone-UID. For the debug screen and for
  /// finding out a new tag's IDs; not for production trips.
  const TagFilter.any()
    : iBeaconUuids = const {},
      eddystoneNamespaces = const {},
      acceptAll = true;

  const TagFilter._({
    required this.iBeaconUuids,
    required this.eddystoneNamespaces,
    required this.acceptAll,
  });

  /// Dashed lowercase UUIDs.
  final Set<String> iBeaconUuids;

  /// 20 lowercase hex digits each.
  final Set<String> eddystoneNamespaces;
  final bool acceptAll;

  bool get isEmpty =>
      !acceptAll && iBeaconUuids.isEmpty && eddystoneNamespaces.isEmpty;

  bool matches(Beacon beacon) {
    if (acceptAll) return true;
    return switch (beacon) {
      IBeacon(:final uuid) => iBeaconUuids.contains(uuid),
      EddystoneUid(:final namespace) => eddystoneNamespaces.contains(namespace),
    };
  }

  /// Hardware filter for the Android scanner. Returns null when nothing can
  /// match (scanning would be pointless).
  BleScanFilter? toScanFilter() {
    if (acceptAll) return const BleScanFilter();
    if (isEmpty) return null;
    return BleScanFilter(
      includeIBeacon: iBeaconUuids.isNotEmpty,
      iBeaconUuids: [for (final u in iBeaconUuids) u.replaceAll('-', '')],
      includeEddystone: eddystoneNamespaces.isNotEmpty,
      eddystoneNamespaces: eddystoneNamespaces.toList(),
    );
  }

  static String _uuid(String value) {
    final hex = normaliseHex(value, 16);
    if (hex == null) throw FormatException('Not an iBeacon UUID', value);
    return uuidFromHex(hex);
  }

  static String _namespace(String value) {
    final hex = normaliseHex(value, 10);
    if (hex == null) throw FormatException('Not an Eddystone namespace', value);
    return hex;
  }
}
