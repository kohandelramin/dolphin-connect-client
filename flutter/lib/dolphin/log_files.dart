import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'zip_writer.dart';

/// DD-39: the app's logs older than this are zipped into one backup and removed.
const kLogKeepDays = 7;

/// Local option (this Windows account): the day of the last cleanup, `YYYY-MM-DD`, so it runs at most once a day.
const kDolphinLogsCleanedLocal = 'dolphin-logs-cleaned';

/// Backups kept in `log\backup`; older ones are removed, so the folder stays small.
const kLogBackupsKept = 3;

/// The marker that replaces a value the scrub removed.
const kScrubbed = '[removed]';

/// One file in the log folder, as listed.
class LogFile {
  final String path;
  final DateTime modified;
  final int size;
  const LogFile(this.path, this.modified, this.size);

  String get name => path.split(RegExp(r'[\\/]')).last;
}

/// Upstream's logs: `%APPDATA%\<app name>\log`, one sub-folder per process (`cm`, `tray`, …; the main window writes
/// to the folder itself). hbb_common config.rs `log_path` and `init_log`. The service's own logs live under the
/// LocalService profile, which a normal user cannot read; the report says what it could read.
String logDirFor({required String appData, required String appName}) => '$appData\\$appName\\log';

String _day(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

/// At most once a day: true unless [lastRun] is today's date.
bool cleanupDue(String lastRun, DateTime now) => lastRun.trim() != _day(now);

String cleanupStamp(DateTime now) => _day(now);

bool _inBackup(String path) => RegExp(r'[\\/]backup[\\/]').hasMatch(path);

/// The files to zip and remove: `.log` files not changed for [kLogKeepDays] days, never the file a process is
/// writing (flexi_logger's `_rCURRENT`), never a backup.
List<LogFile> logsToBackup(List<LogFile> files, DateTime now) {
  final cutoff = now.subtract(const Duration(days: kLogKeepDays));
  return files
      .where((f) =>
          f.name.toLowerCase().endsWith('.log') &&
          !f.name.contains('rCURRENT') &&
          !_inBackup(f.path) &&
          f.modified.isBefore(cutoff))
      .toList();
}

/// The backup's file name, by the day it was made.
String backupName(DateTime now) => 'logs-until-${_day(now)}.zip';

/// Backups beyond the newest [keep], to remove.
List<LogFile> backupsToDrop(List<LogFile> backups, {int keep = kLogBackupsKept}) {
  final sorted = [...backups]..sort((a, b) => b.modified.compareTo(a.modified));
  return sorted.length <= keep ? const [] : sorted.sublist(keep);
}

/// The logs a DD-7 report carries: `.log` files changed in the last [days] days, newest first, up to [budget] bytes of
/// text (a busy day's file is cut to its last part when the report is built).
List<LogFile> reportLogs(List<LogFile> files, DateTime now, {int days = 3, int budget = 12 * 1024 * 1024}) {
  final since = now.subtract(Duration(days: days));
  final recent = files
      .where((f) => f.name.toLowerCase().endsWith('.log') && !_inBackup(f.path) && f.modified.isAfter(since))
      .toList()
    ..sort((a, b) => b.modified.compareTo(a.modified));
  final out = <LogFile>[];
  var used = 0;
  for (final f in recent) {
    if (used >= budget) break;
    out.add(f);
    used += f.size;
  }
  return out;
}

/// The newest backup, if any.
LogFile? newestBackup(List<LogFile> files) {
  final b = files.where((f) => _inBackup(f.path) && f.name.toLowerCase().endsWith('.zip')).toList()
    ..sort((a, b) => b.modified.compareTo(a.modified));
  return b.isEmpty ? null : b.first;
}

// Words after which a log line may carry a secret. Everything after the word, to the end of the line, is removed.
final _secretWord = RegExp(
    r'(pass(word|wd|phrase)?|pwd|secret|token|api[-_ ]?key|private[-_ ]?key|\bkey\b|\bsk\b|\bpk\b|salt|\botp\b|cookie|'
    r'authori[sz]ation|bearer|uuid|hash|signature|credential)',
    caseSensitive: false);

// An ID-like value after a word that names a peer: `peer_id: 123456789`, `id="abc123def"`.
final _idField = RegExp(r'''\b(peer[-_ ]?id|remote[-_ ]?id|peer|id|from|to)\b(\s*[:=]\s*["']?|\s+)([A-Za-z0-9_-]{6,32})''',
    caseSensitive: false);

// A bare RustDesk-style numeric ID: 8 to 11 digits, not part of a longer number, not a time's fraction (`.123456`).
final _bareId = RegExp(r'(?<![\d.])\d{8,11}(?!\d)');

/// DD-7, DD-38, DD-39: what may leave this PC or be kept in a backup. Removes values after words that may carry a
/// secret (password, key, token, salt, hash, uuid …: the rest of that line), and every ID of another PC (values
/// after `peer`, `id` …, and bare 8–11 digit numbers); [ownId], this PC's ID, stays. The input is never a config
/// file: only logs and our own text go through here.
String scrubLog(String text, {String ownId = ''}) {
  final own = ownId.replaceAll(RegExp(r'\s'), '');
  final lines = const LineSplitter().convert(text);
  final out = StringBuffer();
  for (var line in lines) {
    final m = _secretWord.firstMatch(line);
    if (m != null) line = '${line.substring(0, m.end)} $kScrubbed';
    line = line.replaceAllMapped(_idField, (f) {
      final value = f.group(3)!;
      if (own.isNotEmpty && value == own) return f.group(0)!;
      // Words, not IDs: a value with no digit is left as it is ("from server", "to relay").
      if (!value.contains(RegExp(r'\d'))) return f.group(0)!;
      return '${f.group(1)}${f.group(2)}[ID]';
    });
    line = line.replaceAllMapped(_bareId, (b) => own.isNotEmpty && b.group(0) == own ? b.group(0)! : '[ID]');
    out.writeln(line);
  }
  return out.toString();
}

/// Lists every file under [dir] (recursively); nothing when it does not exist.
List<LogFile> listLogFolder(Directory dir) {
  if (!dir.existsSync()) return const [];
  final out = <LogFile>[];
  try {
    for (final e in dir.listSync(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      try {
        final s = e.statSync();
        out.add(LogFile(e.path, s.modified, s.size));
      } catch (_) {}
    }
  } catch (_) {}
  return out;
}

/// A log file's text, cut to its last [maxBytes] (the end is what matters), scrubbed.
String readScrubbed(String path, {required String ownId, int maxBytes = 2 * 1024 * 1024}) {
  final f = File(path);
  final raf = f.openSync();
  try {
    final len = raf.lengthSync();
    final start = len > maxBytes ? len - maxBytes : 0;
    raf.setPositionSync(start);
    final bytes = raf.readSync(len - start);
    final text = utf8.decode(bytes, allowMalformed: true);
    return scrubLog(start > 0 ? '[… earlier part cut]\n$text' : text, ownId: ownId);
  } finally {
    raf.closeSync();
  }
}

/// What a cleanup did.
class LogCleanup {
  final int zipped;
  final int removed;
  final String? backup;
  const LogCleanup(this.zipped, this.removed, this.backup);
}

String _relative(String root, String path) {
  final r = root.endsWith('\\') || root.endsWith('/') ? root : '$root${Platform.pathSeparator}';
  return path.startsWith(r) ? path.substring(r.length) : path.split(RegExp(r'[\\/]')).last;
}

/// DD-39: zips the logs [logsToBackup] picks into `backup\logs-until-<day>.zip` (scrubbed, so the backup is as safe
/// to send as a report), removes them once the zip is on disk, and keeps the newest [kLogBackupsKept] backups. A file
/// still in use cannot be removed and is tried again next time.
LogCleanup cleanLogs(Directory logDir, DateTime now, {String ownId = ''}) {
  final all = listLogFolder(logDir);
  final due = logsToBackup(all, now);
  String? written;
  var removed = 0;
  if (due.isNotEmpty) {
    final entries = <ZipEntry>[];
    for (final f in due) {
      try {
        entries.add(ZipEntry(_relative(logDir.path, f.path), utf8.encode(readScrubbed(f.path, ownId: ownId, maxBytes: 16 * 1024 * 1024)),
            modified: f.modified));
      } catch (_) {}
    }
    if (entries.isNotEmpty) {
      final backupDir = Directory('${logDir.path}${Platform.pathSeparator}backup')..createSync(recursive: true);
      var target = File('${backupDir.path}${Platform.pathSeparator}${backupName(now)}');
      if (target.existsSync()) {
        target = File('${backupDir.path}${Platform.pathSeparator}${backupName(now).replaceAll('.zip', '-${now.millisecondsSinceEpoch}.zip')}');
      }
      final tmp = File('${target.path}.part');
      tmp.writeAsBytesSync(buildZip(entries), flush: true);
      tmp.renameSync(target.path);
      written = target.path;
      for (final f in due) {
        try {
          File(f.path).deleteSync();
          removed++;
        } catch (_) {}
      }
    }
  }
  final backups = listLogFolder(logDir).where((f) => _inBackup(f.path) && f.name.endsWith('.zip')).toList();
  for (final old in backupsToDrop(backups)) {
    try {
      File(old.path).deleteSync();
    } catch (_) {}
  }
  return LogCleanup(due.length, removed, written);
}

/// [cleanLogs] off the window's thread.
Future<LogCleanup> cleanLogsAsync(String logDir, DateTime now, {String ownId = ''}) =>
    Isolate.run(() => cleanLogs(Directory(logDir), now, ownId: ownId));
