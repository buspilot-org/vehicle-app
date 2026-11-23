import 'package:buspilot_vehicle/src/ble/ble.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 11, 23, 7, 30);

const tagA = IBeacon(
  uuid: 'e2c56db5-dffb-48d2-b060-d0f5a71096e0',
  major: 1,
  minor: 1,
);
const tagB = EddystoneUid(
  namespace: 'edd1ebeac04e5defa017',
  instance: '000000000002',
);

BeaconSighting see(
  Beacon b,
  int rssi,
  int seconds, {
  String mac = 'C4:7C:8D:00:00:01',
}) => BeaconSighting(
  beacon: b,
  address: mac,
  rssi: rssi,
  time: t0.add(Duration(seconds: seconds)),
);

Future<void> flush() => Future<void>.delayed(Duration.zero);

void main() {
  late PresenceTracker tracker;
  late List<PresenceEvent> events;

  setUp(() {
    tracker = PresenceTracker(
      config: const PresenceConfig(
        absentAfter: Duration(seconds: 30),
        rssiSmoothing: 0.5,
      ),
      clock: () => t0,
    );
    events = [];
    tracker.events.listen(events.add);
  });

  tearDown(() => tracker.dispose());

  test('first sighting enters, later ones only update', () async {
    tracker.addSighting(see(tagA, -60, 0));
    tracker.addSighting(see(tagA, -70, 1));
    await flush();

    expect(events, hasLength(1));
    expect(events.single, isA<TagEntered>());
    expect(events.single.tagId, tagA.tagId);

    final tag = tracker[tagA.tagId]!;
    expect(tag.sightings, 2);
    expect(tag.rssi, -70);
    expect(tag.smoothedRssi, -65); // 0.5 * -70 + 0.5 * -60
    expect(tag.firstSeen, t0);
    expect(tag.lastSeen, t0.add(const Duration(seconds: 1)));
  });

  test('smoothing converges towards the new level', () {
    tracker.addSighting(see(tagA, -80, 0));
    for (var i = 1; i <= 10; i++) {
      tracker.addSighting(see(tagA, -50, i));
    }
    expect(tracker[tagA.tagId]!.smoothedRssi, closeTo(-50, 0.1));
  });

  test('leaves after absentAfter without sightings, not before', () async {
    tracker.addSighting(see(tagA, -60, 0));
    tracker.addSighting(see(tagB, -60, 20));

    expect(tracker.evictAbsent(t0.add(const Duration(seconds: 29))), isEmpty);
    expect(tracker.isPresent(tagA.tagId), isTrue);

    final gone = tracker.evictAbsent(t0.add(const Duration(seconds: 30)));
    await flush();
    expect(gone.map((t) => t.tagId), [tagA.tagId]);
    expect(tracker.isPresent(tagA.tagId), isFalse);
    expect(tracker.isPresent(tagB.tagId), isTrue);

    final left = events.whereType<TagLeft>().single;
    expect(left.tagId, tagA.tagId);
    expect(left.time, t0.add(const Duration(seconds: 30)));
    expect(left.tag.lastSeen, t0);
  });

  test('evictAbsent uses the clock when no time is given', () {
    tracker.addSighting(see(tagA, -60, -31));
    expect(tracker.evictAbsent().single.tagId, tagA.tagId);
  });

  test('re-enters after leaving', () async {
    tracker.addSighting(see(tagA, -60, 0));
    tracker.evictAbsent(t0.add(const Duration(seconds: 40)));
    tracker.addSighting(see(tagA, -62, 45));
    await flush();

    expect(events.map((e) => e.runtimeType), [TagEntered, TagLeft, TagEntered]);
    final tag = tracker[tagA.tagId]!;
    expect(tag.sightings, 1);
    expect(tag.firstSeen, t0.add(const Duration(seconds: 45)));
  });

  test('an out-of-order sighting does not move lastSeen back', () {
    tracker.addSighting(see(tagA, -60, 10));
    tracker.addSighting(see(tagA, -60, 5));
    expect(tracker[tagA.tagId]!.lastSeen, t0.add(const Duration(seconds: 10)));
  });

  test('tracks the latest MAC address for the same tag ID', () {
    tracker.addSighting(see(tagA, -60, 0, mac: 'AA:AA:AA:AA:AA:01'));
    tracker.addSighting(see(tagA, -60, 1, mac: 'AA:AA:AA:AA:AA:02'));
    expect(tracker.present, hasLength(1));
    expect(tracker[tagA.tagId]!.address, 'AA:AA:AA:AA:AA:02');
  });

  test('present is sorted by smoothed RSSI, strongest first', () {
    tracker.addSighting(see(tagA, -80, 0));
    tracker.addSighting(see(tagB, -55, 0));
    expect(tracker.present.map((t) => t.tagId), [tagB.tagId, tagA.tagId]);
  });

  test('minRssi drops weak sightings', () async {
    final t = PresenceTracker(config: const PresenceConfig(minRssi: -75));
    final ev = <PresenceEvent>[];
    t.events.listen(ev.add);
    t.addSighting(see(tagA, -90, 0));
    expect(t.isPresent(tagA.tagId), isFalse);
    t.addSighting(see(tagA, -70, 1));
    await flush();
    expect(t.isPresent(tagA.tagId), isTrue);
    expect(ev, hasLength(1));
    t.dispose();
  });

  test('clear forgets tags without leave events and notifies', () async {
    var notified = 0;
    tracker.addSighting(see(tagA, -60, 0));
    tracker.addListener(() => notified++);
    tracker.clear();
    await flush();
    expect(tracker.present, isEmpty);
    expect(events.whereType<TagLeft>(), isEmpty);
    expect(notified, 1);
  });
}
