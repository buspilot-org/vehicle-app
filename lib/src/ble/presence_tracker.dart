import 'dart:async';

import 'package:flutter/foundation.dart';

import 'beacon.dart';

/// Tuning for [PresenceTracker].
class PresenceConfig {
  const PresenceConfig({
    this.absentAfter = const Duration(seconds: 30),
    this.rssiSmoothing = 0.3,
    this.minRssi,
  }) : assert(rssiSmoothing > 0 && rssiSmoothing <= 1);

  /// A tag not seen for this long counts as gone and a [TagLeft] is emitted.
  /// Should be several times the tags' advertising interval, because scans
  /// miss individual advertisements.
  final Duration absentAfter;

  /// Weight of a new reading in the exponential moving average of RSSI
  /// (1 = no smoothing).
  final double rssiSmoothing;

  /// Sightings weaker than this (dBm) are ignored, e.g. to drop tags outside
  /// the bus. Null accepts all.
  final int? minRssi;
}

/// Snapshot of a tag that is currently present.
@immutable
class PresentTag {
  const PresentTag({
    required this.beacon,
    required this.address,
    required this.firstSeen,
    required this.lastSeen,
    required this.rssi,
    required this.smoothedRssi,
    required this.sightings,
  });

  final Beacon beacon;

  /// Last MAC address the tag was seen with (debug only).
  final String address;
  final DateTime firstSeen;
  final DateTime lastSeen;

  /// Last raw RSSI, dBm.
  final int rssi;

  /// Exponentially smoothed RSSI, dBm.
  final double smoothedRssi;

  /// Number of sightings since the tag entered.
  final int sightings;

  String get tagId => beacon.tagId;

  @override
  String toString() =>
      'PresentTag($tagId, rssi: ${smoothedRssi.toStringAsFixed(1)}, '
      'lastSeen: $lastSeen)';
}

/// Enter or leave event for a tag.
sealed class PresenceEvent {
  const PresenceEvent(this.tag, this.time);

  /// State of the tag at the time of the event.
  final PresentTag tag;
  final DateTime time;

  String get tagId => tag.tagId;
}

/// First sighting of a tag that was not present.
final class TagEntered extends PresenceEvent {
  const TagEntered(super.tag, super.time);

  @override
  String toString() => 'TagEntered($tagId at $time)';
}

/// Tag not seen for [PresenceConfig.absentAfter]. [time] is when the absence
/// was detected; [PresentTag.lastSeen] is when it was last heard.
final class TagLeft extends PresenceEvent {
  const TagLeft(super.tag, super.time);

  @override
  String toString() => 'TagLeft($tagId at $time, last seen ${tag.lastSeen})';
}

/// Aggregates beacon sightings into the set of tags currently present.
///
/// Pure logic without timers: call [addSighting] for every sighting and
/// [evictAbsent] periodically (the scan service does this every second).
/// Listeners ([ChangeNotifier]) are notified on every change, including RSSI
/// updates; [events] carries only enter/leave.
class PresenceTracker extends ChangeNotifier {
  PresenceTracker({
    this.config = const PresenceConfig(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final PresenceConfig config;
  final DateTime Function() _clock;
  final _tags = <String, PresentTag>{};
  final _events = StreamController<PresenceEvent>.broadcast();

  /// Enter and leave events, delivered asynchronously.
  Stream<PresenceEvent> get events => _events.stream;

  /// Present tags, strongest smoothed RSSI first.
  List<PresentTag> get present =>
      _tags.values.toList()
        ..sort((a, b) => b.smoothedRssi.compareTo(a.smoothedRssi));

  bool isPresent(String tagId) => _tags.containsKey(tagId);

  PresentTag? operator [](String tagId) => _tags[tagId];

  void addSighting(BeaconSighting s) {
    final minRssi = config.minRssi;
    if (minRssi != null && s.rssi < minRssi) return;

    final old = _tags[s.tagId];
    if (old == null) {
      final tag = PresentTag(
        beacon: s.beacon,
        address: s.address,
        firstSeen: s.time,
        lastSeen: s.time,
        rssi: s.rssi,
        smoothedRssi: s.rssi.toDouble(),
        sightings: 1,
      );
      _tags[s.tagId] = tag;
      _emit(TagEntered(tag, s.time));
    } else {
      final a = config.rssiSmoothing;
      _tags[s.tagId] = PresentTag(
        beacon: s.beacon,
        address: s.address,
        firstSeen: old.firstSeen,
        // Sightings may arrive slightly out of order; never move backwards.
        lastSeen: s.time.isAfter(old.lastSeen) ? s.time : old.lastSeen,
        rssi: s.rssi,
        smoothedRssi: a * s.rssi + (1 - a) * old.smoothedRssi,
        sightings: old.sightings + 1,
      );
    }
    notifyListeners();
  }

  /// Removes tags not seen for [PresenceConfig.absentAfter] and emits
  /// [TagLeft] for each. Returns the removed tags.
  List<PresentTag> evictAbsent([DateTime? now]) {
    final t = now ?? _clock();
    final gone = [
      for (final tag in _tags.values)
        if (t.difference(tag.lastSeen) >= config.absentAfter) tag,
    ];
    if (gone.isEmpty) return const [];
    for (final tag in gone) {
      _tags.remove(tag.tagId);
      _emit(TagLeft(tag, t));
    }
    notifyListeners();
    return gone;
  }

  /// Forgets all tags without emitting [TagLeft] (stopping the scan does not
  /// mean the tags left).
  void clear() {
    if (_tags.isEmpty) return;
    _tags.clear();
    notifyListeners();
  }

  void _emit(PresenceEvent e) {
    if (!_events.isClosed) _events.add(e);
  }

  @override
  void dispose() {
    _events.close();
    super.dispose();
  }
}
