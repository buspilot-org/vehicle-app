import 'dart:typed_data';

import 'package:buspilot_vehicle/src/ble/beacon.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hex string with optional spaces to bytes.
Uint8List hex(String s) {
  final clean = s.replaceAll(' ', '');
  return Uint8List.fromList([
    for (var i = 0; i < clean.length; i += 2)
      int.parse(clean.substring(i, i + 2), radix: 16),
  ]);
}

/// Android `ScanRecord.getBytes()` returns the advertisement plus scan
/// response, zero-padded to 62 bytes.
Uint8List padded(Uint8List adv) => Uint8List(62)..setRange(0, adv.length, adv);

void main() {
  group('iBeacon', () {
    // Flags, then manufacturer data: Apple 0x004C, type 02 15, UUID
    // E2C56DB5-DFFB-48D2-B060-D0F5A71096E0 (the AirLocate UUID many beacons
    // ship with), major 0x1234, minor 0xABCD, tx power 0xC5 (-59 dBm at 1 m).
    final frame = hex(
      '02 01 06 '
      '1A FF 4C 00 02 15 E2 C5 6D B5 DF FB 48 D2 B0 60 D0 F5 A7 10 96 E0 '
      '12 34 AB CD C5',
    );

    test('parses UUID, major, minor and tx power', () {
      final b = parseAdvertisement(frame);
      expect(b, isA<IBeacon>());
      b as IBeacon;
      expect(b.uuid, 'e2c56db5-dffb-48d2-b060-d0f5a71096e0');
      expect(b.major, 0x1234);
      expect(b.minor, 0xABCD);
      expect(b.txPower, -59);
      expect(
        b.tagId,
        'ibeacon:e2c56db5-dffb-48d2-b060-d0f5a71096e0:4660:43981',
      );
    });

    test('parses a zero-padded Android scan record with scan response', () {
      // Scan response: complete local name "EYE".
      final withName = Uint8List.fromList([...frame, ...hex('04 09 45 59 45')]);
      expect(parseAdvertisement(padded(withName)), parseAdvertisement(frame));
    });

    test('ignores other Apple manufacturer data', () {
      // Apple "Nearby Info" (type 0x10), sent by iPhones.
      expect(
        parseAdvertisement(hex('02 01 1A 0A FF 4C 00 10 05 0B 1C 7E 2B 4E')),
        isNull,
      );
    });

    test('ignores iBeacon layout from another company', () {
      final other = Uint8List.fromList(frame)..[5] = 0x9A; // Company 0x009A.
      expect(parseAdvertisement(other), isNull);
    });

    test('ignores a truncated frame', () {
      expect(parseAdvertisement(frame.sublist(0, frame.length - 1)), isNull);
    });
  });

  group('Eddystone-UID', () {
    // Example from the Eddystone spec: namespace EDD1EBEAC04E5DEFA017,
    // instance 0BDB87539B67, tx power at 0 m 0xE7 (-25 dBm). Complete list of
    // 16-bit service UUIDs (FEAA), then service data with two RFU bytes.
    final frame = hex(
      '02 01 06 03 03 AA FE '
      '17 16 AA FE 00 E7 ED D1 EB EA C0 4E 5D EF A0 17 0B DB 87 53 9B 67 00 00',
    );

    test('parses namespace, instance and tx power', () {
      final b = parseAdvertisement(frame);
      expect(b, isA<EddystoneUid>());
      b as EddystoneUid;
      expect(b.namespace, 'edd1ebeac04e5defa017');
      expect(b.instance, '0bdb87539b67');
      expect(b.txPower, -25);
      expect(b.tagId, 'eddystone:edd1ebeac04e5defa017:0bdb87539b67');
    });

    test('accepts a frame without the reserved bytes', () {
      final short = hex(
        '02 01 06 03 03 AA FE '
        '15 16 AA FE 00 E7 ED D1 EB EA C0 4E 5D EF A0 17 0B DB 87 53 9B 67',
      );
      expect(parseAdvertisement(short), parseAdvertisement(frame));
    });

    test('ignores Eddystone-URL and TLM frames', () {
      // URL frame (0x10): "https://goo.gl/xyz".
      expect(
        parseAdvertisement(
          hex('02 01 06 03 03 AA FE 0C 16 AA FE 10 EB 03 67 6F 6F 2E 67 6C'),
        ),
        isNull,
      );
      // TLM frame (0x20).
      expect(
        parseAdvertisement(
          hex(
            '02 01 06 03 03 AA FE 11 16 AA FE 20 00 0B B8 17 00 00 00 01 00 00 00 00 64',
          ),
        ),
        isNull,
      );
    });

    test('ignores service data for other UUIDs', () {
      final other = Uint8List.fromList(frame)..[9] = 0xAB; // UUID 0xABAA.
      expect(parseAdvertisement(other), isNull);
    });
  });

  group('robustness', () {
    test('empty and malformed input', () {
      expect(parseAdvertisement(Uint8List(0)), isNull);
      expect(parseAdvertisement(Uint8List(62)), isNull);
      expect(
        parseAdvertisement(hex('FF FF 4C 00')),
        isNull,
      ); // Length beyond end.
    });
  });

  group('hex helpers', () {
    test('normaliseHex', () {
      expect(
        normaliseHex('E2C56DB5-DFFB-48D2-B060-D0F5A71096E0', 16),
        'e2c56db5dffb48d2b060d0f5a71096e0',
      );
      expect(
        normaliseHex('ED D1 EB EA C0 4E 5D EF A0 17', 10),
        'edd1ebeac04e5defa017',
      );
      expect(normaliseHex('edd1', 10), isNull);
      expect(normaliseHex('zzd1ebeac04e5defa017', 10), isNull);
    });
  });
}
