import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'digits.dart';
import 'log_files.dart';
import 'switches.dart';
import 'zip_writer.dart';

/// DD-7 «گزارش برای پشتیبانی» and DD-48 «فرستادن عکس صفحه به پشتیبانی»: the customer's app sends a zip of its logs, or
/// a PNG of the customer's own screen, to the portal with this PC's ID and machine UUID (the same pair the heartbeat
/// and «با من تماس بگیرید» send; no account). Portal side: app/src/app/rd/api/dolphin/{diagnostics,screenshot}/route.ts
/// and app/src/lib/diagnostics.ts in the portal repo.
enum UploadKind { diagnostics, screenshot }

/// The portal's caps (DIAGNOSTICS_MAX_BYTES, SCREENSHOT_MAX_BYTES).
const kReportMaxBytes = 5 * 1024 * 1024;
const kScreenshotMaxBytes = 3 * 1024 * 1024;

/// The portal keeps at most 500 characters of the note.
const kUploadNoteMax = 500;

/// Both buttons follow the portal's `diagnostics-upload` switch: hidden hides them, available and forced show them.
bool uploadShown(SwitchMode mode) => mode != SwitchMode.hidden;

String _path(UploadKind k) => k == UploadKind.diagnostics ? 'diagnostics' : 'screenshot';
String contentTypeOf(UploadKind k) => k == UploadKind.diagnostics ? 'application/zip' : 'image/png';
int maxBytesOf(UploadKind k) => k == UploadKind.diagnostics ? kReportMaxBytes : kScreenshotMaxBytes;

/// `{portal}/rd/api/dolphin/<kind>?id=…&uuid=…&note=…`; an empty note is left out.
Uri uploadUri(String portal, UploadKind kind, {required String id, required String uuid, String note = ''}) {
  final base = portal.endsWith('/') ? portal.substring(0, portal.length - 1) : portal;
  final n = note.trim().replaceAll(RegExp(r'\s+'), ' ');
  final cut = String.fromCharCodes(n.runes.take(kUploadNoteMax));
  return Uri.parse('$base/rd/api/dolphin/${_path(kind)}').replace(queryParameters: {
    'id': id,
    'uuid': uuid,
    if (cut.isNotEmpty) 'note': cut,
  });
}

/// What the customer reads after a send.
class UploadAnswer {
  final bool ok;
  final String text;
  const UploadAnswer(this.ok, this.text);
}

const kUploadNetworkText = 'به پورتال دلفین وصل نشد؛ اینترنت را بررسی کنید و دوباره امتحان کنید.';
const kUploadUnclearText = 'پاسخ پورتال دلفین روشن نبود؛ کمی بعد دوباره امتحان کنید.';

/// The portal's answer in short Persian, per reason (src/lib/diagnostics.ts AcceptResult).
UploadAnswer uploadAnswer(int status, String body, {UploadKind kind = UploadKind.diagnostics, String? retryAfter}) {
  final what = kind == UploadKind.diagnostics ? 'گزارش' : 'عکس صفحه';
  if (status == 429) {
    final secs = int.tryParse(retryAfter ?? '') ?? 0;
    final when = secs >= 3600
        ? '${faDigits('${(secs / 3600).ceil()}')} ساعت دیگر'
        : secs > 60
            ? '${faDigits('${(secs / 60).ceil()}')} دقیقه‌ی دیگر'
            : 'کمی بعد';
    return UploadAnswer(false, 'چند بار پشت سر هم فرستاده شد؛ $when دوباره امتحان کنید.');
  }
  if (status == 413) return UploadAnswer(false, '$what بزرگ‌تر از حد مجاز است؛ با پشتیبانی دلفین تماس بگیرید.');
  if (status == 400) return UploadAnswer(false, '$what پذیرفته نشد؛ دوباره امتحان کنید.');
  if (status != 200) return const UploadAnswer(false, kUploadNetworkText);
  Map<String, dynamic>? v;
  try {
    final d = jsonDecode(body);
    if (d is Map<String, dynamic>) v = d;
  } catch (_) {}
  if (v == null) return const UploadAnswer(false, kUploadUnclearText);
  if (v['ok'] == true) return UploadAnswer(true, '$what فرستاده شد؛ کارشناس دلفین آن را در صفحه‌ی این رایانه می‌بیند.');
  return UploadAnswer(false, switch (v['reason']) {
    'off' => 'پورتال دلفین فعلاً $what نمی‌گیرد؛ با پشتیبانی دلفین تماس بگیرید.',
    'invalid' => '$what پذیرفته نشد؛ دوباره امتحان کنید.',
    'too_big' => '$what بزرگ‌تر از حد مجاز است؛ با پشتیبانی دلفین تماس بگیرید.',
    'not_found' => 'دلفین هنوز این رایانه را نمی‌شناسد؛ چند دقیقه بعد دوباره امتحان کنید یا تماس بگیرید.',
    'not_linked' => 'این رایانه هنوز به سازمانی در دلفین وصل نیست؛ با پشتیبانی دلفین تماس بگیرید.',
    'stale' => 'این رایانه چند دقیقه است به سرور دلفین وصل نبوده؛ اینترنت را بررسی کنید و دوباره امتحان کنید.',
    'disabled' => 'فرستادن $what برای سازمان شما خاموش است.',
    'too_many' => 'روزی حداکثر سه بار می‌شود $what فرستاد؛ فردا دوباره امتحان کنید یا تماس بگیرید.',
    _ => kUploadUnclearText,
  });
}

/// Sends [bytes] to [uri]. Never throws: a failure is an answer.
Future<UploadAnswer> postUpload(Uri uri, Uint8List bytes, UploadKind kind,
    {Duration timeout = const Duration(seconds: 120)}) async {
  if (bytes.length > maxBytesOf(kind)) return uploadAnswer(413, '', kind: kind);
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final request = await client.postUrl(uri).timeout(timeout);
    request.headers.contentType = ContentType.parse(contentTypeOf(kind));
    request.contentLength = bytes.length;
    request.add(bytes);
    final response = await request.close().timeout(timeout);
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    return uploadAnswer(response.statusCode, body, kind: kind, retryAfter: response.headers.value('retry-after'));
  } catch (_) {
    return const UploadAnswer(false, kUploadNetworkText);
  } finally {
    client.close(force: true);
  }
}

/// The diagnostic text's lines: (label, value). Only this PC's own facts; never a password, key, token, config secret
/// or another PC's ID (and it goes through [scrubLog] like the logs).
class DiagnosticFacts {
  final String appVersion;
  final String windows;
  final bool installed;
  final String service;
  final List<String> network;
  final List<String> checks;
  final String ownId;
  final DateTime at;
  const DiagnosticFacts(
      {required this.appVersion,
      required this.windows,
      required this.installed,
      required this.service,
      this.network = const [],
      this.checks = const [],
      this.ownId = '',
      required this.at});
}

String _stamp(DateTime t) =>
    '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// DD-7's `diagnostic.txt` and DD-38's «ذخیره‌ی گزارش»: short, Persian labels, Latin values (it is read by staff and
/// pasted into chats).
String diagnosticText(DiagnosticFacts f) {
  final b = StringBuffer()
    ..writeln('گزارش دلفین کانکت')
    ..writeln('زمان: ${_stamp(f.at)}')
    ..writeln('نسخه‌ی برنامه: ${f.appVersion}')
    ..writeln('ویندوز: ${f.windows}')
    ..writeln('نصب: ${f.installed ? 'نصب‌شده' : 'بدون نصب (قابل حمل)'}')
    ..writeln('سرویس: ${f.service}');
  if (f.ownId.isNotEmpty) b.writeln('شناسه‌ی این رایانه: ${f.ownId}');
  if (f.network.isNotEmpty) {
    b.writeln();
    b.writeln('وضعیت شبکه:');
    for (final l in f.network) {
      b.writeln('  $l');
    }
  }
  if (f.checks.isNotEmpty) {
    b.writeln();
    b.writeln('بررسی سلامت:');
    for (final l in f.checks) {
      b.writeln('  $l');
    }
  }
  return scrubLog(b.toString(), ownId: f.ownId);
}

/// DD-7: the report zip: `diagnostic.txt`, the recent logs (scrubbed, each cut to its last 2 MB), and DD-39's newest
/// backup when it fits. Kept under [maxBytes]: when the zip is too big the oldest logs are left out first, then the
/// backup, then every log is cut shorter.
Uint8List buildReportZip(
    {required String diagnostic,
    required String logRoot,
    required List<LogFile> logs,
    LogFile? backup,
    required String ownId,
    int maxBytes = kReportMaxBytes - 64 * 1024}) {
  final texts = <ZipEntry>[];
  for (final f in logs) {
    try {
      texts.add(ZipEntry('logs/${_relative(logRoot, f.path)}', utf8.encode(readScrubbed(f.path, ownId: ownId)),
          modified: f.modified));
    } catch (_) {}
  }
  ZipEntry? backupEntry;
  if (backup != null) {
    try {
      backupEntry = ZipEntry('backup/${backup.name}', File(backup.path).readAsBytesSync(), modified: backup.modified);
    } catch (_) {}
  }
  return fitReportZip(diagnostic: diagnostic, logs: texts, backup: backupEntry, maxBytes: maxBytes);
}

/// [buildReportZip] off the window's thread: reading, scrubbing and zipping a few MB of logs takes a moment.
Future<Uint8List> buildReportZipAsync(
        {required String diagnostic, required String logRoot, required List<LogFile> logs, LogFile? backup, required String ownId}) =>
    Isolate.run(() => buildReportZip(diagnostic: diagnostic, logRoot: logRoot, logs: logs, backup: backup, ownId: ownId));

/// The shrinking part of [buildReportZip], on entries already read (testable without files).
Uint8List fitReportZip({required String diagnostic, required List<ZipEntry> logs, ZipEntry? backup, required int maxBytes}) {
  final head = ZipEntry('diagnostic.txt', utf8.encode(diagnostic));
  var kept = [...logs];
  var withBackup = backup;
  while (true) {
    final zip = buildZip([head, ...kept, if (withBackup != null) withBackup]);
    if (zip.length <= maxBytes) return zip;
    if (kept.length > 1) {
      kept = kept.sublist(0, kept.length - 1); // logs come newest first: the oldest goes
    } else if (withBackup != null) {
      withBackup = null;
    } else if (kept.isNotEmpty && kept.first.data.length > 64 * 1024) {
      final d = kept.first.data;
      kept = [ZipEntry(kept.first.name, d.sublist(d.length ~/ 2), modified: kept.first.modified)];
    } else {
      return buildZip([head]);
    }
  }
}

String _relative(String root, String path) {
  final r = root.endsWith('\\') || root.endsWith('/') ? root : '$root${Platform.pathSeparator}';
  return (path.startsWith(r) ? path.substring(r.length) : path.split(RegExp(r'[\\/]')).last).replaceAll('\\', '/');
}
