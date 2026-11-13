import 'dart:io';

import 'package:flutter/material.dart';

import '../models/platform_model.dart';
import 'presence.dart';
import 'receive_folder.dart';
import 'session_frame.dart';
import 'switch_row.dart';
import 'switches.dart';
import 'theme.dart';
import 'theme_option.dart';
import 'update.dart';

/// Plan 19 C5: the customer's few settings, opened by ⚙ in the main window's footer. Only what a customer should know:
/// whether closing the window asks (ADR-0016), the coloured frame during a session (C3), where received files land
/// (DD-12), the look (like Windows, light or dark) and the update check (DD-20). Everything else the portal decides for
/// the organization, and a choice the portal fixed is shown dimmed with «سازمان تعیین کرده».
const kSettingsTitle = 'تنظیمات';
const kAskOnCloseLabel = 'هنگام بستن پنجره بپرس';
const kReceiveFolderRowLabel = 'پوشه‌ی فایل‌های دریافتی';
const kOpenFolderLabel = 'باز کردن';
const kThemeLabel = 'پوسته';
const kOrgDecidesLine = 'بقیه را پورتال برای سازمان شما تعیین می‌کند.';
const kOrgDecidedNote = 'سازمان تعیین کرده';

/// «هنگام بستن پنجره بپرس» is on while no answer is remembered (presence.dart).
bool closeAsks(String remembered) => remembered != 'stay' && remembered != 'quit';

/// What to keep when the switch moves: on forgets the answer (ask again); off keeps «در دسترس بماند», the answer that
/// keeps Dolphin reachable (the tray menu can still close it completely).
String closeAskValue(bool ask) => ask ? '' : 'stay';

/// The switch can be moved only while the portal's `stay-in-tray` leaves the choice to the person at the PC.
bool closeAskLocked(SwitchMode stayInTray) => stayInTray != SwitchMode.available;

/// The folder's own name for the row («دریافتی دلفین»), the full path in its tooltip.
String folderName(String path) {
  final parts = path.split(RegExp(r'[\\/]')).where((p) => p.isNotEmpty).toList();
  return parts.isEmpty ? path : parts.last;
}

/// The view. Pure: values in, callbacks out.
class DolphinCustomerSettingsView extends StatelessWidget {
  final bool askOnClose;

  /// Null shows the switch dimmed with «سازمان تعیین کرده».
  final ValueChanged<bool>? onAskOnClose;
  final bool frame;
  final ValueChanged<bool> onFrame;

  /// The receive folder's path; '' hides the row (the portal's `receive-folder` hides it).
  final String receiveFolder;
  final VoidCallback? onOpenFolder;
  final DolphinThemeChoice theme;
  final ValueChanged<DolphinThemeChoice> onTheme;

  /// «بررسی نسخه‌ی تازه» (update.dart DolphinUpdateCheckButton in the app).
  final Widget updateCheck;
  final VoidCallback onClose;

  const DolphinCustomerSettingsView(
      {super.key,
      required this.askOnClose,
      required this.onAskOnClose,
      required this.frame,
      required this.onFrame,
      required this.receiveFolder,
      this.onOpenFolder,
      required this.theme,
      required this.onTheme,
      required this.updateCheck,
      required this.onClose});

  @override
  Widget build(BuildContext context) =>
      DolphinLight(paint: false, child: Material(color: DolphinColors.surface, child: Builder(builder: _build)));

  Widget _row(String label, Widget trailing, {String? tooltip}) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(children: [
          Expanded(
              child: Text(label, style: TextStyle(color: DolphinColors.ink, fontSize: 13.5, fontWeight: FontWeight.w600))),
          const SizedBox(width: 8),
          tooltip == null ? trailing : Tooltip(message: tooltip, child: trailing),
        ]),
      );

  Widget _build(BuildContext context) {
    final onOpenFolder = this.onOpenFolder;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
                child: Text(kSettingsTitle,
                    style: TextStyle(color: DolphinColors.ink, fontSize: 16, fontWeight: FontWeight.w800))),
            IconButton(
              key: const ValueKey('dolphin-settings-close'),
              tooltip: 'بستن',
              onPressed: onClose,
              icon: Icon(Icons.close, size: 20, color: DolphinColors.muted),
            ),
          ]),
          const SizedBox(height: 4),
          DolphinSwitchRow(
            switchKey: const ValueKey('dolphin-settings-ask-close'),
            label: kAskOnCloseLabel,
            value: askOnClose,
            onChanged: onAskOnClose,
            note: onAskOnClose == null ? kOrgDecidedNote : null,
          ),
          DolphinSwitchRow(
            switchKey: const ValueKey('dolphin-settings-frame'),
            label: kFrameSettingLabel,
            value: frame,
            onChanged: onFrame,
          ),
          if (receiveFolderShown(receiveFolder))
            _row(
              kReceiveFolderRowLabel,
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(folderName(receiveFolder), style: TextStyle(color: DolphinColors.muted, fontSize: 12.5)),
                if (onOpenFolder != null)
                  TextButton(
                    key: const ValueKey('dolphin-settings-open-folder'),
                    onPressed: onOpenFolder,
                    style: TextButton.styleFrom(
                        foregroundColor: DolphinColors.azureText,
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                    child: const Text(kOpenFolderLabel),
                  ),
              ]),
              tooltip: receiveFolder,
            ),
          _row(
            kThemeLabel,
            DropdownButton<DolphinThemeChoice>(
              key: const ValueKey('dolphin-settings-theme'),
              value: theme,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(DolphinRadii.field),
              dropdownColor: DolphinColors.surface,
              style: TextStyle(color: DolphinColors.ink, fontSize: 13, fontFamily: kDolphinFont),
              iconEnabledColor: DolphinColors.muted,
              items: [
                for (final c in DolphinThemeChoice.values)
                  DropdownMenuItem(value: c, child: Text(kThemeChoiceLabels[c]!)),
              ],
              onChanged: (c) {
                if (c != null) onTheme(c);
              },
            ),
          ),
          const SizedBox(height: 6),
          updateCheck,
          const SizedBox(height: 12),
          Divider(height: 1, color: DolphinColors.line),
          const SizedBox(height: 8),
          Text(kOrgDecidesLine, style: TextStyle(color: DolphinColors.muted, fontSize: 12, height: 1.6)),
        ]),
      ),
    );
  }
}

/// The settings with their state: options read when it opens, written on each change.
class DolphinCustomerSettings extends StatefulWidget {
  final VoidCallback onClose;
  const DolphinCustomerSettings({super.key, required this.onClose});

  @override
  State<DolphinCustomerSettings> createState() => _DolphinCustomerSettingsState();
}

class _DolphinCustomerSettingsState extends State<DolphinCustomerSettings> {
  late SwitchMode _stayInTray;
  late bool _ask;
  late bool _frame;
  String _folder = '';

  @override
  void initState() {
    super.initState();
    _stayInTray =
        DolphinSwitches.parse(bind.mainGetOptionSync(key: kDolphinSwitchesOption)).mode(DolphinSwitch.stayInTray);
    _ask = closeAction(_stayInTray, bind.mainGetLocalOption(key: kDolphinCloseChoiceOption)) == CloseAction.ask;
    _frame = frameOn(bind.mainGetLocalOption(key: kDolphinFrameLocal));
    bind.mainGetCommon(key: kDolphinReceiveDirKey).then((p) {
      if (mounted) setState(() => _folder = p);
    });
  }

  Future<void> _openFolder() async {
    try {
      await Directory(_folder).create(recursive: true);
      await Process.run('explorer.exe', [_folder]);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => DolphinCustomerSettingsView(
        askOnClose: _ask,
        onAskOnClose: closeAskLocked(_stayInTray)
            ? null
            : (v) {
                setState(() => _ask = v);
                bind.mainSetLocalOption(key: kDolphinCloseChoiceOption, value: closeAskValue(v));
              },
        frame: _frame,
        onFrame: (v) {
          setState(() => _frame = v);
          bind.mainSetLocalOption(key: kDolphinFrameLocal, value: frameValue(v));
        },
        receiveFolder: _folder,
        onOpenFolder: Platform.isWindows ? _openFolder : null,
        theme: themeChoiceFrom(bind.mainGetLocalOption(key: kDolphinThemeChoiceLocal)),
        onTheme: (c) async {
          await setCustomerThemeChoice(c);
          if (mounted) setState(() {});
        },
        updateCheck: const DolphinUpdateCheckButton(),
        onClose: widget.onClose,
      );
}

/// ⚙ in the footer.
Future<void> showDolphinCustomerSettings(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        clipBehavior: Clip.antiAlias,
        backgroundColor: DolphinColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DolphinRadii.card)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: DolphinCustomerSettings(onClose: () => Navigator.of(ctx).pop()),
        ),
      ),
    );
