import 'dart:typed_data';

/// A beacon frame decoded from a BLE advertisement.
///
/// [tagId] is the stable identifier used everywhere else (presence, reports).
/// It is derived from the beacon's own IDs, not from the MAC address, because
/// some tags rotate their address. Privacy: only this ID is ever stored or
/// sent; the link to a passenger is held by the operator.
sealed class Beacon {
  const Beacon({this.txPower});

  /// Calibrated power in dBm: at 1 m for iBeacon, at 0 m for Eddystone.
  final int? txPower;

  String get tagId;
}

/// Apple iBeacon: proximity UUID, major, minor.
final class IBeacon extends Beacon {
  const IBeacon({
    required this.uuid,
    required this.major,
    required this.minor,
    super.txPower,
  });

  /// Lowercase, with dashes: `e2c56db5-dffb-48d2-b060-d0f5a71096e0`.
  final String uuid;
  final int major;
  final int minor;

  @override
  String get tagId => 'ibeacon:$uuid:$major:$minor';

  @override
  bool operator ==(Object other) =>
      other is IBeacon &&
      other.uuid == uuid &&
      other.major == major &&
      other.minor == minor &&
      other.txPower == txPower;

  @override
  int get hashCode => Object.hash(uuid, major, minor, txPower);

  @override
  String toString() => 'IBeacon($tagId, txPower: $txPower)';
}

/// Google Eddystone-UID: 10-byte namespace, 6-byte instance.
final class EddystoneUid extends Beacon {
  const EddystoneUid({
    required this.namespace,
    required this.instance,
    super.txPower,
  });

  /// 20 lowercase hex digits.
  final String namespace;

  /// 12 lowercase hex digits.
  final String instance;

  @override
  String get tagId => 'eddystone:$namespace:$instance';

  @override
  bool operator ==(Object other) =>
      other is EddystoneUid &&
      other.namespace == namespace &&
      other.instance == instance &&
      other.txPower == txPower;

  @override
  int get hashCode => Object.hash(namespace, instance, txPower);

  @override
  String toString() => 'EddystoneUid($tagId, txPower: $txPower)';
}

/// One received advertisement that contained a beacon frame.
class BeaconSighting {
  const BeaconSighting({
    required this.beacon,
    required this.address,
    required this.rssi,
    required this.time,
  });

  final Beacon beacon;

  /// Bluetooth MAC address as reported by Android. Kept for debugging only.
  final String address;

  /// Signal strength in dBm.
  final int rssi;
  final DateTime time;

  String get tagId => beacon.tagId;
}

/// Lowercase hex of [bytes] without separators.
String hexOf(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Normalises a hex ID typed by an operator (any case, optional dashes or
/// spaces) to lowercase hex digits; returns null if it is not [length] bytes.
String? normaliseHex(String value, int length) {
  final clean = value.replaceAll(RegExp(r'[\s:-]'), '').toLowerCase();
  if (clean.length != length * 2 || !RegExp(r'^[0-9a-f]+$').hasMatch(clean)) {
    return null;
  }
  return clean;
}

/// Formats 32 hex digits as a dashed UUID.
String uuidFromHex(String hex) =>
    '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
    '${hex.substring(16, 20)}-${hex.substring(20)}';

int _signed8(int b) => b >= 0x80 ? b - 0x100 : b;

const _appleCompanyId = 0x004C;
const _eddystoneServiceUuid16 = 0xFEAA;

/// AD types, Bluetooth Core Supplement part A.
const _adServiceData16 = 0x16;
const _adManufacturerSpecific = 0xFF;

/// Parses raw advertisement bytes (a sequence of `length, type, data` AD
/// structures, as returned by Android `ScanRecord.getBytes()`) and returns the
/// first iBeacon or Eddystone-UID frame found, or null.
///
/// Malformed structures end parsing; trailing zero padding is ignored.
Beacon? parseAdvertisement(Uint8List bytes) {
  var i = 0;
  while (i < bytes.length) {
    final len = bytes[i];
    if (len == 0) break; // Padding.
    final end = i + 1 + len;
    if (end > bytes.length) break; // Truncated.
    final type = bytes[i + 1];
    final data = Uint8List.sublistView(bytes, i + 2, end);
    final beacon = switch (type) {
      _adManufacturerSpecific => parseIBeacon(data),
      _adServiceData16 => parseEddystoneUid(data),
      _ => null,
    };
    if (beacon != null) return beacon;
    i = end;
  }
  return null;
}

/// Parses the data of a manufacturer-specific AD structure (company ID
/// little-endian first). iBeacon layout after company ID 0x004C:
/// `02 15 <uuid:16> <major:2 BE> <minor:2 BE> <txPower:1 signed>`.
IBeacon? parseIBeacon(Uint8List data) {
  if (data.length < 25) return null;
  final company = data[0] | (data[1] << 8);
  if (company != _appleCompanyId || data[2] != 0x02 || data[3] != 0x15) {
    return null;
  }
  return IBeacon(
    uuid: uuidFromHex(hexOf(data.sublist(4, 20))),
    major: (data[20] << 8) | data[21],
    minor: (data[22] << 8) | data[23],
    txPower: _signed8(data[24]),
  );
}

/// Parses the data of a 16-bit service data AD structure (UUID little-endian
/// first). Eddystone-UID frame for UUID 0xFEAA:
/// `00 <txPower@0m:1 signed> <namespace:10> <instance:6> [<rfu:2>]`.
/// The two reserved bytes are optional; some beacons omit them.
EddystoneUid? parseEddystoneUid(Uint8List data) {
  if (data.length < 20) return null;
  final uuid = data[0] | (data[1] << 8);
  if (uuid != _eddystoneServiceUuid16 || data[2] != 0x00) return null;
  return EddystoneUid(
    txPower: _signed8(data[3]),
    namespace: hexOf(data.sublist(4, 14)),
    instance: hexOf(data.sublist(14, 20)),
  );
}
