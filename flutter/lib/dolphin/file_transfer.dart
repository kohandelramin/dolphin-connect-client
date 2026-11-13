import 'dart:convert';

import 'package:flutter/material.dart';

import 'digits.dart';
import 'theme.dart';

/// DD-30: the technician's file window (upstream flutter/lib/desktop/pages/file_manager_page.dart and
/// flutter/lib/models/file_model.dart, hooks marked `Dolphin Connect (DD-30)`):
/// - files dropped from Windows on either side go to the folder open on the customer's PC, by the same path as
///   «ارسال» (upstream's drop asked the customer's PC to send the dropped local paths, which never worked);
/// - the transfer list is a queue in Persian: percent, «توقف», «تلاش دوباره», «ادامه», «پاک کردن از فهرست»;
/// - pinned folders, kept in this technician app (a local option, so per technician), for each side;
/// - «کپی مسیر» on a file or folder.
/// The transfers themselves are upstream's: the same messages over the same file-transfer connection.

// ---- Drag and drop ----

const kDropTitle = 'رها کنید تا به رایانه‌ی مشتری فرستاده شود';
const kDropNoFolder = 'هنوز پوشه‌ای در رایانه‌ی مشتری باز نشده است؛ چند لحظه صبر کنید.';

/// A dropped file or folder, as Windows gives it.
typedef DroppedItem = ({String path, String name, bool isDir, int size});

/// What a drop sends: the dropped items, or nothing while the customer's folder is not known yet (the transfer needs
/// a destination). Drives are never sent.
List<DroppedItem> dropToSend(List<DroppedItem> dropped, String remoteFolder) {
  if (remoteFolder.trim().isEmpty) return const [];
  return [for (final d in dropped) if (!_isDriveRoot(d.path)) d];
}

bool _isDriveRoot(String path) => RegExp(r'^[A-Za-z]:\\?$').hasMatch(path) || path == '/';

/// The mask over the file window while files are dragged over it: where they will land.
class DolphinDropMask extends StatelessWidget {
  final String remoteFolder;
  const DolphinDropMask({super.key, required this.remoteFolder});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            key: const ValueKey('dolphin-drop-mask'),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DolphinColors.azureSoft.withOpacity(0.92),
              borderRadius: BorderRadius.circular(DolphinRadii.card),
              border: Border.all(color: DolphinColors.azure, width: 2),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.file_upload_outlined, size: 40, color: DolphinColors.azureText),
                  const SizedBox(height: 8),
                  Text(remoteFolder.trim().isEmpty ? kDropNoFolder : kDropTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: kDolphinFont, fontWeight: FontWeight.w800, color: DolphinColors.ink, fontSize: 15)),
                  if (remoteFolder.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(remoteFolder,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}

// ---- The queue ----

/// The percent inside the bar, in Persian: «۴۵٪».
String transferPercent(double fraction) => '${faDigits((fraction.clamp(0, 1) * 100).toStringAsFixed(0))}٪';

/// «۲ از ۵ فایل» (upstream: "2/5 files").
String transferFiles(int done, int count) => '${faDigits('$done')} از ${faDigits('$count')} فایل';

const kJobStop = 'توقف';
const kJobRetry = 'تلاش دوباره';
const kJobResume = 'ادامه';
const kJobRemove = 'پاک کردن از فهرست';

enum DolphinJobAction { resume, stop, retry, remove }

/// The buttons on a row of the queue. [state] and [type] are upstream's JobState and JobType names (`inProgress`,
/// `transfer`…), [err] the job's error text ("cancel" after «توقف»), [canRetry] whether the transfer's request was kept.
List<DolphinJobAction> jobActions({required String type, required String state, required String err, required bool canRetry}) {
  if (type != 'transfer') return const [DolphinJobAction.remove]; // deleting: upstream's one button
  switch (state) {
    case 'none':
    case 'inProgress':
      return const [DolphinJobAction.stop];
    case 'paused':
      return const [DolphinJobAction.resume, DolphinJobAction.stop];
    case 'error':
      return [if (canRetry) DolphinJobAction.retry, DolphinJobAction.remove];
    case 'done':
      return [if (canRetry && err == 'cancel') DolphinJobAction.retry, DolphinJobAction.remove];
    default:
      return const [DolphinJobAction.remove];
  }
}

/// What a transfer asked for, kept so «تلاش دوباره» can ask exactly the same again (the arguments of upstream's
/// `sessionSendFiles`).
class DolphinTransfer {
  final String path;
  final String to;
  final bool isDir;
  final bool includeHidden;
  final bool isRemote;
  const DolphinTransfer({required this.path, required this.to, required this.isDir, required this.includeHidden,
      required this.isRemote});
}

/// The row's buttons, right to left, each with its Persian tooltip.
class DolphinJobButtons extends StatelessWidget {
  final List<DolphinJobAction> actions;
  final void Function(DolphinJobAction action) onAction;
  const DolphinJobButtons({super.key, required this.actions, required this.onAction});

  static (IconData, String) _look(DolphinJobAction a) => switch (a) {
        DolphinJobAction.resume => (Icons.play_arrow_rounded, kJobResume),
        DolphinJobAction.stop => (Icons.stop_rounded, kJobStop),
        DolphinJobAction.retry => (Icons.refresh_rounded, kJobRetry),
        DolphinJobAction.remove => (Icons.close_rounded, kJobRemove),
      };

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: IconButton.filled(
              key: ValueKey('dolphin-job-${a.name}'),
              tooltip: _look(a).$2,
              onPressed: () => onAction(a),
              style: IconButton.styleFrom(
                backgroundColor: a == DolphinJobAction.stop ? DolphinColors.danger : DolphinColors.azure,
                foregroundColor: Colors.white,
                minimumSize: const Size(32, 32),
                fixedSize: const Size(32, 32),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinTheme.light.radiusSmall)),
              ),
              icon: Icon(_look(a).$1, size: 18),
            ),
          ),
      ]);
}

// ---- Pinned folders ----

/// One local option in the technician app; each Windows account has its own, so pins are kept per technician.
const kDolphinPinsKey = 'dolphin-pinned-folders';
const kMaxPins = 12;

const kPinsTooltip = 'پوشه‌های سنجاق‌شده';
const kPinThis = 'سنجاق کردن این پوشه';
const kPinsEmpty = 'هنوز پوشه‌ای سنجاق نشده است.';
const kUnpin = 'برداشتن سنجاق';

/// The pins of one side (`local` or `remote`) from the stored JSON; anything unreadable is no pins.
List<String> pinsFor(String stored, String side) {
  try {
    final data = jsonDecode(stored);
    if (data is! Map) return const [];
    final list = data[side];
    if (list is! List) return const [];
    return [for (final p in list) if (p is String && p.trim().isNotEmpty) p];
  } catch (_) {
    return const [];
  }
}

/// [stored] with [side]'s pins replaced by [pins] (the other side kept).
String withPins(String stored, String side, List<String> pins) {
  Map<String, dynamic> data = {};
  try {
    final d = jsonDecode(stored);
    if (d is Map) data = Map<String, dynamic>.from(d);
  } catch (_) {}
  data[side] = pins;
  return jsonEncode(data);
}

bool _samePath(String a, String b) => _norm(a) == _norm(b);
String _norm(String p) {
  var s = p.trim();
  while (s.length > 1 && (s.endsWith('\\') || s.endsWith('/')) && !RegExp(r'^[A-Za-z]:\\$').hasMatch(s)) {
    s = s.substring(0, s.length - 1);
  }
  return s.toLowerCase(); // Windows paths: one pin for C:\Dolphin and c:\dolphin\
}

/// [pins] with [path] added at the end (once, at most [kMaxPins]: the oldest goes).
List<String> addPin(List<String> pins, String path) {
  if (path.trim().isEmpty || pins.any((p) => _samePath(p, path))) return pins;
  final next = [...pins, path.trim()];
  return next.length > kMaxPins ? next.sublist(next.length - kMaxPins) : next;
}

List<String> removePin(List<String> pins, String path) => [for (final p in pins) if (!_samePath(p, path)) p];

bool isPinned(List<String> pins, String path) => pins.any((p) => _samePath(p, path));

/// The pin button beside «خانه»: the pinned folders of this side, «سنجاق کردن این پوشه», and an unpin per folder.
/// [load] and [save] read and write the stored JSON ([kDolphinPinsKey]); [current] is the open folder.
class DolphinPinMenu extends StatelessWidget {
  final String side;
  final String Function() current;
  final void Function(String path) onOpen;
  final String Function() load;
  final void Function(String value) save;
  const DolphinPinMenu(
      {super.key, required this.side, required this.current, required this.onOpen, required this.load, required this.save});

  @override
  Widget build(BuildContext context) => PopupMenuButton<(String, String)>(
        key: ValueKey('dolphin-pins-$side'),
        tooltip: kPinsTooltip,
        icon: Icon(Icons.push_pin_outlined, color: Theme.of(context).tabBarTheme.labelColor),
        onSelected: (choice) {
          final (what, path) = choice;
          final pins = pinsFor(load(), side);
          if (what == 'open') onOpen(path);
          if (what == 'pin') save(withPins(load(), side, addPin(pins, path)));
          if (what == 'unpin') save(withPins(load(), side, removePin(pins, path)));
        },
        itemBuilder: (context) {
          final pins = pinsFor(load(), side);
          final here = current();
          return [
            if (pins.isEmpty) const PopupMenuItem(enabled: false, child: Text(kPinsEmpty)),
            for (final p in pins)
              PopupMenuItem(
                value: ('open', p),
                child: Row(children: [
                  const Icon(Icons.folder_outlined, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(p, textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    tooltip: kUnpin,
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () => Navigator.of(context).pop(('unpin', p)),
                  ),
                ]),
              ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: ('pin', here),
              enabled: here.trim().isNotEmpty && !isPinned(pins, here),
              child: const Row(children: [
                Icon(Icons.push_pin, size: 18),
                SizedBox(width: 8),
                Flexible(child: Text(kPinThis, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ];
        },
      );
}

// ---- Copy a path ----

const kCopyPath = 'کپی مسیر';
const kPathCopied = 'مسیر کپی شد';
