import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// One file in a zip (DD-7 report, DD-39 log backup).
class ZipEntry {
  final String name;
  final List<int> data;
  final DateTime modified;
  ZipEntry(this.name, this.data, {DateTime? modified}) : modified = modified ?? DateTime(2026);
}

final Uint32List _crcTable = () {
  final t = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    t[n] = c;
  }
  return t;
}();

/// CRC-32 as zip wants it (IEEE 802.3).
int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

int _dosTime(DateTime t) => (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
int _dosDate(DateTime t) => ((t.year < 1980 ? 0 : t.year - 1980) << 9) | (t.month << 5) | t.day;

/// A plain zip (deflate, or stored when deflate does not help), UTF-8 names, no zip64: our files are a few MB.
/// Small and std-only (dart:io's raw deflate), so the app needs no new package; Windows' Explorer and the portal's
/// download open it as any zip.
Uint8List buildZip(List<ZipEntry> entries) {
  final out = BytesBuilder(copy: false);
  final central = BytesBuilder(copy: false);
  var offset = 0;
  for (final e in entries) {
    final name = utf8.encode(e.name.replaceAll('\\', '/'));
    final crc = crc32(e.data);
    final deflated = ZLibEncoder(raw: true, level: 6).convert(e.data);
    final stored = deflated.length >= e.data.length;
    final body = stored ? e.data : deflated;
    final method = stored ? 0 : 8;
    final time = _dosTime(e.modified), date = _dosDate(e.modified);

    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little) // version needed
      ..setUint16(6, 0x0800, Endian.little) // UTF-8 names
      ..setUint16(8, method, Endian.little)
      ..setUint16(10, time, Endian.little)
      ..setUint16(12, date, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, body.length, Endian.little)
      ..setUint32(22, e.data.length, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(body);

    final dir = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little) // made by
      ..setUint16(6, 20, Endian.little) // version needed
      ..setUint16(8, 0x0800, Endian.little)
      ..setUint16(10, method, Endian.little)
      ..setUint16(12, time, Endian.little)
      ..setUint16(14, date, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, body.length, Endian.little)
      ..setUint32(24, e.data.length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    central
      ..add(dir.buffer.asUint8List())
      ..add(name);
    offset += 30 + name.length + body.length;
  }
  final dirBytes = central.takeBytes();
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, dirBytes.length, Endian.little)
    ..setUint32(16, offset, Endian.little);
  out
    ..add(dirBytes)
    ..add(end.buffer.asUint8List());
  return out.takeBytes();
}
