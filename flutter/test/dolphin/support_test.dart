import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_hbb/dolphin/log_files.dart';
import 'package:flutter_hbb/dolphin/screenshot.dart';
import 'package:flutter_hbb/dolphin/support_upload.dart';
import 'package:flutter_hbb/dolphin/switches.dart';
import 'package:flutter_hbb/dolphin/zip_writer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Plan 18 Phase 4: DD-7 report, DD-48 screenshot, DD-39 log cleanup; the scrub that keeps secrets and other PCs' IDs
// out of everything that leaves the PC.

/// Reads a zip back through its central directory: name → bytes (inflated), checking each CRC.
Map<String, List<int>> _unzip(Uint8List zip) {
  final d = ByteData.sublistView(zip);
  var end = zip.length - 22;
  while (d.getUint32(end, Endian.little) != 0x06054b50) {
    end--;
  }
  final count = d.getUint16(end + 10, Endian.little);
  var p = d.getUint32(end + 16, Endian.little);
  final out = <String, List<int>>{};
  for (var i = 0; i < count; i++) {
    expect(d.getUint32(p, Endian.little), 0x02014b50);
    final method = d.getUint16(p + 10, Endian.little);
    final crc = d.getUint32(p + 16, Endian.little);
    final csize = d.getUint32(p + 20, Endian.little);
    final usize = d.getUint32(p + 24, Endian.little);
    final nlen = d.getUint16(p + 28, Endian.little);
    final local = d.getUint32(p + 42, Endian.little);
    final name = utf8.decode(zip.sublist(p + 46, p + 46 + nlen));
    final lnlen = d.getUint16(local + 26, Endian.little);
    final lxlen = d.getUint16(local + 28, Endian.little);
    final start = local + 30 + lnlen + lxlen;
    final body = zip.sublist(start, start + csize);
    final data = method == 8 ? ZLibDecoder(raw: true).convert(body) : body;
    expect(data.length, usize, reason: name);
    expect(crc32(data), crc, reason: name);
    out[name] = data;
    p += 46 + nlen;
  }
  return out;
}

void main() {
  group('zip', () {
    test('crc32 matches the standard check value', () {
      expect(crc32(ascii.encode('123456789')), 0xCBF43926);
    });

    test('entries come back whole, deflated or stored, with UTF-8 names', () {
      final big = utf8.encode('log line\n' * 2000);
      final zip = buildZip([ZipEntry('diagnostic.txt', utf8.encode('گزارش')), ZipEntry('logs/cm/a.log', big), ZipEntry('e', [])]);
      expect(zip.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]); // the portal checks this magic
      final files = _unzip(zip);
      expect(utf8.decode(files['diagnostic.txt']!), 'گزارش');
      expect(files['logs/cm/a.log'], big);
      expect(files['e'], isEmpty);
      expect(zip.length, lessThan(big.length ~/ 10));
    });
  });

  group('scrub', () {
    test('values after secret words are removed to the end of the line', () {
      final out = scrubLog('login ok\npassword: hunter2\nset token=abc.def\nKey: AAAA/BBBB=\nsalt "x1y2"\nuuid=Zm9v');
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('abc.def')));
      expect(out, isNot(contains('AAAA')));
      expect(out, isNot(contains('x1y2')));
      expect(out, isNot(contains('Zm9v')));
      expect(out, contains('login ok'));
      expect(out, contains('password $kScrubbed'));
    });

    test('other PCs\' IDs go, this PC\'s stays', () {
      const log = '[2026-11-13 10:00:00.123456 +03:30] INFO Connection from 987654321 to 123456789\n'
          'peer_id: abc123def ok\nid="555666777" done\nremote id 10203040 closed\nport 21116 pid 4242';
      final out = scrubLog(log, ownId: '123 456 789');
      expect(out, isNot(contains('987654321')));
      expect(out, isNot(contains('abc123def')));
      expect(out, isNot(contains('555666777')));
      expect(out, isNot(contains('10203040')));
      expect(out, contains('123456789'));
      expect(out, contains('10:00:00.123456')); // a time's fraction is not an ID
      expect(out, contains('21116'));
      expect(out, contains('4242'));
    });

    test('words after "from" and "to" are left alone', () {
      expect(scrubLog('reply from server to relay'), contains('from server to relay'));
    });
  });

  group('log files (DD-39)', () {
    final now = DateTime(2026, 11, 13, 9);
    LogFile f(String path, int daysOld, [int size = 100]) => LogFile(path, now.subtract(Duration(days: daysOld)), size);

    test('cleanup runs at most once a day', () {
      expect(cleanupDue('', now), isTrue);
      expect(cleanupDue('2026-11-12', now), isTrue);
      expect(cleanupDue(cleanupStamp(now), now), isFalse);
    });

    test('only old .log files, never the current one or a backup', () {
      final picked = logsToBackup([
        f(r'C:\log\DolphinConnect_r2026-10-01.log', 40),
        f(r'C:\log\cm\DolphinConnect_r2026-11-05.log', 8),
        f(r'C:\log\DolphinConnect_rCURRENT.log', 30),
        f(r'C:\log\DolphinConnect_r2026-11-10.log', 3),
        f(r'C:\log\backup\old.log', 30),
        f(r'C:\log\notes.txt', 30),
      ], now);
      expect(picked.map((e) => e.name), ['DolphinConnect_r2026-10-01.log', 'DolphinConnect_r2026-11-05.log']);
      expect(backupName(now), 'logs-until-2026-11-13.zip');
    });

    test('the newest backups are kept', () {
      final b = [f(r'C:\log\backup\a.zip', 30), f(r'C:\log\backup\b.zip', 1), f(r'C:\log\backup\c.zip', 20), f(r'C:\log\backup\d.zip', 10)];
      expect(backupsToDrop(b).map((e) => e.name), ['a.zip']);
      expect(newestBackup([...b, f(r'C:\log\x.log', 0)])!.name, 'b.zip');
    });

    test('a report takes recent logs, newest first, within its budget', () {
      final picked = reportLogs([f('/l/a.log', 1, 600), f('/l/b.log', 0, 600), f('/l/c.log', 5), f('/l/backup/x.log', 0)], now,
          budget: 500);
      expect(picked.map((e) => e.name), ['b.log']);
    });

    test('cleanLogs zips scrubbed old logs, removes them and keeps the rest', () {
      final dir = Directory.systemTemp.createTempSync('dolphin-logs');
      addTearDown(() => dir.deleteSync(recursive: true));
      final old = File('${dir.path}${Platform.pathSeparator}app_r2026-10-01.log')
        ..writeAsStringSync('connect to 987654321\npassword=secret1\n');
      old.setLastModifiedSync(now.subtract(const Duration(days: 30)));
      final fresh = File('${dir.path}${Platform.pathSeparator}app_rCURRENT.log')..writeAsStringSync('today');
      final r = cleanLogs(dir, now, ownId: '111222333');
      expect(r.zipped, 1);
      expect(r.removed, 1);
      expect(old.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
      final files = _unzip(File(r.backup!).readAsBytesSync());
      final text = utf8.decode(files['app_r2026-10-01.log']!);
      expect(text, isNot(contains('987654321')));
      expect(text, isNot(contains('secret1')));
      // Nothing more to do the same day.
      expect(cleanLogs(dir, now).zipped, 0);
    });
  });

  group('upload (DD-7, DD-48)', () {
    test('the switch hides both buttons only when hidden', () {
      expect(uploadShown(SwitchMode.hidden), isFalse);
      expect(uploadShown(SwitchMode.available), isTrue);
      expect(uploadShown(SwitchMode.forced), isTrue);
    });

    test('the address carries ID, UUID and a cut note', () {
      final u = uploadUri('https://support.dolphindev.ir/', UploadKind.diagnostics, id: '123456789', uuid: 'a+b/c=', note: '  چاپگر   کار نمی‌کند ');
      expect(u.path, '/rd/api/dolphin/diagnostics');
      expect(u.queryParameters, {'id': '123456789', 'uuid': 'a+b/c=', 'note': 'چاپگر کار نمی‌کند'});
      final s = uploadUri('https://x', UploadKind.screenshot, id: '1', uuid: 'u', note: 'ن' * 600);
      expect(s.path, '/rd/api/dolphin/screenshot');
      expect(s.queryParameters['note']!.length, kUploadNoteMax);
      expect(uploadUri('https://x', UploadKind.screenshot, id: '1', uuid: 'u').queryParameters.containsKey('note'), isFalse);
      expect(contentTypeOf(UploadKind.diagnostics), 'application/zip');
      expect(contentTypeOf(UploadKind.screenshot), 'image/png');
    });

    test('every answer of the portal has its own short Persian text', () {
      expect(uploadAnswer(200, '{"ok":true}').ok, isTrue);
      final texts = <String>{};
      for (final r in ['off', 'invalid', 'too_big', 'not_found', 'not_linked', 'stale', 'disabled', 'too_many']) {
        final a = uploadAnswer(200, '{"ok":false,"reason":"$r"}');
        expect(a.ok, isFalse, reason: r);
        expect(a.text, isNot(kUploadUnclearText), reason: r);
        texts.add(a.text);
      }
      expect(texts.length, 8);
      expect(uploadAnswer(200, '{"ok":false,"reason":"not_linked"}').text, contains('سازمان'));
      expect(uploadAnswer(200, '{"ok":false,"reason":"too_many"}').text, contains('سه بار'));
      expect(uploadAnswer(429, '', retryAfter: '3600').text, contains('۱ ساعت'));
      expect(uploadAnswer(413, '', kind: UploadKind.screenshot).text, contains('عکس صفحه'));
      expect(uploadAnswer(502, '<html>').text, kUploadNetworkText);
      expect(uploadAnswer(200, '<html>').text, kUploadUnclearText);
    });

    test('the diagnostic text has no secret and no other PC\'s ID', () {
      final t = diagnosticText(DiagnosticFacts(
          appVersion: '2.1.0',
          windows: 'Windows 10 Pro 10.0 (Build 19045)',
          installed: true,
          service: 'روشن است.',
          network: ['سرور دلفین: وصل', 'آخرین اتصال از 987654321'],
          checks: ['token: abc'],
          ownId: '123456789',
          at: DateTime(2026, 11, 13, 10, 30)));
      expect(t, contains('2.1.0'));
      expect(t, contains('123456789'));
      expect(t, isNot(contains('987654321')));
      expect(t, isNot(contains('abc')));
    });

    test('a report too big for the portal drops old logs first, then the backup', () {
      final r = Random(7);
      final rnd = List<int>.generate(300 * 1024, (_) => r.nextInt(256)); // does not compress
      final logs = [ZipEntry('logs/new.log', rnd), ZipEntry('logs/old.log', rnd)];
      final backup = ZipEntry('backup/b.zip', rnd);
      final all = _unzip(fitReportZip(diagnostic: 'd', logs: logs, backup: backup, maxBytes: 2 * 1024 * 1024));
      expect(all.keys, ['diagnostic.txt', 'logs/new.log', 'logs/old.log', 'backup/b.zip']);
      final two = _unzip(fitReportZip(diagnostic: 'd', logs: logs, backup: backup, maxBytes: 700 * 1024));
      expect(two.keys, ['diagnostic.txt', 'logs/new.log', 'backup/b.zip']);
      final one = _unzip(fitReportZip(diagnostic: 'd', logs: logs, backup: backup, maxBytes: 400 * 1024));
      expect(one.keys, ['diagnostic.txt', 'logs/new.log']);
      final cut = fitReportZip(diagnostic: 'd', logs: logs, backup: backup, maxBytes: 200 * 1024);
      expect(cut.length, lessThanOrEqualTo(200 * 1024));
      expect(_unzip(cut).keys.first, 'diagnostic.txt');
    });
  });

  group('screenshot (DD-48)', () {
    RawScreen raw(int w, int h, {bool noisy = false}) {
      final b = Uint8List(w * h * 4);
      final r = Random(3);
      for (var i = 0; i < b.length; i++) {
        b[i] = noisy ? r.nextInt(256) : (i % 4 == 0 ? 200 : 30); // BGRA, alpha 0 as GDI leaves it
      }
      return RawScreen(w, h, b);
    }

    test('a small screen goes out at full size, opaque, colours in the right order', () {
      final png = pngUnder(raw(64, 40))!;
      final back = img.decodePng(png)!;
      expect(back.width, 64);
      final p = back.getPixel(0, 0);
      expect([p.r, p.g, p.b], [30, 30, 200]); // B=200 stays blue
      expect(back.numChannels, 3);
    });

    test('a picture over the cap is made smaller until it fits', () {
      final png = pngUnder(raw(800, 600, noisy: true), maxBytes: 300 * 1024)!;
      expect(png.length, lessThanOrEqualTo(300 * 1024));
      expect(img.decodePng(png)!.width, lessThan(800));
      expect(nextWidth(1000, 4000000, 3000000), lessThan(1000));
      expect(nextWidth(400, 100000000, 1000), 320);
    });
  });
}
