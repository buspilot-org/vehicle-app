import 'presence_tracker.dart';

/// Detected tags in the form they will be sent to Traccar.
///
/// Not wired into tracking yet. The OsmAnd protocol passes unknown query
/// parameters through as position attributes, so a position request can carry
/// `tag1Id=…&tag1Rssi=…&tag2Id=…`. The names follow Traccar's Teltonika
/// decoder (`tagNId`, `tagNRssi`), so phone and installed tracker produce the
/// same attributes on the server.
///
/// Privacy: only tag IDs and signal strength, never names or MAC addresses.
class TagReport {
  const TagReport(this.tags);

  /// Builds a report from the tracker's present tags (strongest first),
  /// capped at [maxTags] to keep the request URL short.
  factory TagReport.fromTracker(PresenceTracker tracker, {int maxTags = 50}) =>
      TagReport(tracker.present.take(maxTags).toList());

  final List<PresentTag> tags;

  bool get isEmpty => tags.isEmpty;

  /// Attributes numbered from 1 in list order, e.g.
  /// `{tag1Id: ibeacon:…:1:2, tag1Rssi: -61}`. RSSI is the smoothed value
  /// rounded to whole dBm.
  Map<String, String> toOsmAndAttributes() => {
    for (final (i, tag) in tags.indexed) ...{
      'tag${i + 1}Id': tag.tagId,
      'tag${i + 1}Rssi': tag.smoothedRssi.round().toString(),
    },
  };
}
