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
}
