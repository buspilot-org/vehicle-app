import 'package:buspilot_vehicle/src/ble/ble.dart';
import 'package:flutter_test/flutter_test.dart';

const uuid = 'e2c56db5-dffb-48d2-b060-d0f5a71096e0';
const ns = 'edd1ebeac04e5defa017';

void main() {
  group('TagFilter', () {
    final filter = TagFilter(
      iBeaconUuids: ['E2C56DB5-DFFB-48D2-B060-D0F5A71096E0'],
      eddystoneNamespaces: ['EDD1 EBEA C04E 5DEF A017'],
    );

    test('normalises configured IDs', () {
      expect(filter.iBeaconUuids, {uuid});
      expect(filter.eddystoneNamespaces, {ns});
    });

    test('matches only configured UUIDs and namespaces', () {
      expect(
        filter.matches(const IBeacon(uuid: uuid, major: 1, minor: 2)),
        isTrue,
      );
      expect(
        filter.matches(
          const IBeacon(
            uuid: 'fda50693-a4e2-4fb1-afcf-c6eb07647825',
            major: 1,
            minor: 2,
          ),
        ),
        isFalse,
      );
      expect(
        filter.matches(
          const EddystoneUid(namespace: ns, instance: '000000000001'),
        ),
        isTrue,
      );
      expect(
        filter.matches(
          const EddystoneUid(
            namespace: '00000000000000000000',
            instance: '000000000001',
          ),
        ),
        isFalse,
      );
    });

    test('empty filter matches nothing and yields no scan filter', () {
      final empty = TagFilter();
      expect(empty.isEmpty, isTrue);
      expect(
        empty.matches(const IBeacon(uuid: uuid, major: 1, minor: 2)),
        isFalse,
      );
      expect(empty.toScanFilter(), isNull);
    });

    test('any matches everything and scans all formats', () {
      const any = TagFilter.any();
      expect(
        any.matches(const IBeacon(uuid: uuid, major: 1, minor: 2)),
        isTrue,
      );
      final sf = any.toScanFilter()!;
      expect(sf.includeIBeacon && sf.includeEddystone, isTrue);
      expect(sf.iBeaconUuids, isEmpty);
    });

    test('scan filter carries hex IDs and skips unused formats', () {
      final onlyIBeacon = TagFilter(iBeaconUuids: [uuid]).toScanFilter()!;
      expect(onlyIBeacon.iBeaconUuids, ['e2c56db5dffb48d2b060d0f5a71096e0']);
      expect(onlyIBeacon.includeEddystone, isFalse);
      expect(filter.toScanFilter()!.eddystoneNamespaces, [ns]);
    });

    test('rejects invalid IDs', () {
      expect(
        () => TagFilter(iBeaconUuids: ['not-a-uuid']),
        throwsFormatException,
      );
      expect(
        () => TagFilter(eddystoneNamespaces: ['edd1']),
        throwsFormatException,
      );
    });
  });

  group('TagReport', () {
    PresentTag tag(Beacon b, double rssi) => PresentTag(
      beacon: b,
      address: 'C4:7C:8D:00:00:01',
      firstSeen: DateTime.utc(2026),
      lastSeen: DateTime.utc(2026),
      rssi: rssi.round(),
      smoothedRssi: rssi,
      sightings: 1,
    );

    test('numbers tags from 1 with ID and rounded RSSI, no MAC', () {
      final report = TagReport([
        tag(const IBeacon(uuid: uuid, major: 1, minor: 2), -61.4),
        tag(const EddystoneUid(namespace: ns, instance: '0bdb87539b67'), -77.6),
      ]);
      expect(report.toOsmAndAttributes(), {
        'tag1Id': 'ibeacon:$uuid:1:2',
        'tag1Rssi': '-61',
        'tag2Id': 'eddystone:$ns:0bdb87539b67',
        'tag2Rssi': '-78',
      });
    });

    test('fromTracker takes the strongest tags up to maxTags', () {
      final tracker = PresenceTracker();
      for (var i = 0; i < 5; i++) {
        tracker.addSighting(
          BeaconSighting(
            beacon: IBeacon(uuid: uuid, major: 1, minor: i),
            address: 'x',
            rssi: -90 + i,
            time: DateTime.utc(2026),
          ),
        );
      }
      final report = TagReport.fromTracker(tracker, maxTags: 2);
      expect(report.tags.map((t) => (t.beacon as IBeacon).minor), [4, 3]);
      expect(
        TagReport.fromTracker(PresenceTracker()).toOsmAndAttributes(),
        isEmpty,
      );
      tracker.dispose();
    });
  });
}
