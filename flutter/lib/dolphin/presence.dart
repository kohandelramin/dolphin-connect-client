import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models/platform_model.dart';
import 'switches.dart';
import 'theme.dart';

/// ADR-0016 (DD-35): closing the customer window asks whether Dolphin Connect stays available beside the clock or
/// closes completely. A remembered answer is kept for this Windows user on this PC.
const kDolphinCloseChoiceOption = 'dolphin-close-choice';

enum CloseChoice { stay, quit }

enum CloseAction { ask, stay, quit }

/// What a close does, from the portal's `stay-in-tray` switch and a remembered answer ('stay', 'quit', anything else:
/// none). «پنهان» always quits without asking; «اجباری» always stays (the tray menu can still quit).
CloseAction closeAction(SwitchMode stayInTray, String remembered) {
  switch (stayInTray) {
    case SwitchMode.hidden:
      return CloseAction.quit;
    case SwitchMode.forced:
      return CloseAction.stay;
    case SwitchMode.available:
      if (remembered == 'stay') return CloseAction.stay;
      if (remembered == 'quit') return CloseAction.quit;
      return CloseAction.ask;
  }
}

/// The value to keep after the question: '' when «انتخاب را به خاطر بسپار» is not ticked.
String rememberValue(CloseChoice choice, bool remember) => !remember
    ? ''
    : choice == CloseChoice.stay
        ? 'stay'
        : 'quit';

const kCloseTitle = 'دلفین کانکت بسته شود؟';
const kCloseStay = 'در دسترس بماند (کنار ساعت)';
const kCloseStayHint = 'نماد دلفین کنار ساعت می‌ماند و کارشناس دلفین فقط با اجازه‌ی پورتال وصل می‌شود.';
const kCloseQuit = 'بستن کامل';
const kCloseQuitHint = 'تا برنامه را دوباره باز نکنید، هیچ کس نمی‌تواند وصل شود.';
const kCloseRemember = 'انتخاب را به خاطر بسپار';
const kCloseCancel = 'انصراف';

/// The question. Pure: [onChoose] gets the answer and whether to remember it; [onCancel] keeps the window open.
class DolphinCloseDialogView extends StatefulWidget {
  final void Function(CloseChoice choice, bool remember) onChoose;
  final VoidCallback onCancel;
  const DolphinCloseDialogView({super.key, required this.onChoose, required this.onCancel});

  @override
  State<DolphinCloseDialogView> createState() => _DolphinCloseDialogViewState();
}

class _DolphinCloseDialogViewState extends State<DolphinCloseDialogView> {
  bool _remember = false;

  Widget _option(CloseChoice choice, IconData icon, String label, String hint, {required bool primary}) {
    final fg = primary ? Colors.white : DolphinColors.ink;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: primary ? DolphinColors.azure : DolphinColors.azureSoft,
        borderRadius: BorderRadius.circular(DolphinRadii.control),
        child: InkWell(
          key: ValueKey('dolphin-close-${choice.name}'),
          borderRadius: BorderRadius.circular(DolphinRadii.control),
          onTap: () => widget.onChoose(choice, _remember),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(hint,
                      style: TextStyle(
                          color: primary ? Colors.white : DolphinColors.muted, fontSize: 12, height: 1.5)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text(kCloseTitle, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _option(CloseChoice.stay, Icons.schedule, kCloseStay, kCloseStayHint, primary: true),
          const SizedBox(height: 8),
          _option(CloseChoice.quit, Icons.power_settings_new, kCloseQuit, kCloseQuitHint, primary: false),
          const SizedBox(height: 6),
          CheckboxListTile(
            key: const ValueKey('dolphin-close-remember'),
            value: _remember,
            onChanged: (v) => setState(() => _remember = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text(kCloseRemember, style: TextStyle(fontSize: 13)),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: widget.onCancel, child: const Text(kCloseCancel)),
          ),
        ]),
      ),
    );
  }
}

// Set once «بستن کامل» is under way: upstream's shutdown closes the window again, which must not ask a second time.
bool _quitting = false;

/// Hook in upstream's `onWindowClose` (tabbar_widget.dart) for the customer main window. Returns true when it has
/// handled the close: the window is hidden into the tray (still registered as active, so upstream's
/// `onActiveWindowChanged` does not end the app), or the customer cancelled. Returns false to let upstream's close run,
/// which ends the process: «بستن کامل». See src/dolphin_system.rs for why a hidden window still counts as open.
Future<bool> dolphinHandleMainWindowClose(BuildContext context) async {
  if (_quitting) return false;
  final mode = DolphinSwitches.parse(bind.mainGetOptionSync(key: kDolphinSwitchesOption)).mode(DolphinSwitch.stayInTray);
  var action = closeAction(mode, bind.mainGetLocalOption(key: kDolphinCloseChoiceOption));
  if (action == CloseAction.ask) {
    if (!context.mounted) return false;
    final answer = await showDialog<(CloseChoice, bool)>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: DolphinCloseDialogView(
            onChoose: (choice, remember) => Navigator.of(context).pop((choice, remember)),
            onCancel: () => Navigator.of(context).pop(),
          ),
        ),
      ),
    );
    if (answer == null) return true; // cancelled: the window stays as it is
    final (choice, remember) = answer;
    final keep = rememberValue(choice, remember);
    if (keep.isNotEmpty) await bind.mainSetLocalOption(key: kDolphinCloseChoiceOption, value: keep);
    action = choice == CloseChoice.stay ? CloseAction.stay : CloseAction.quit;
  }
  if (action == CloseAction.quit) {
    _quitting = true;
    return false;
  }
  // A portable app has no tray yet (an installed one got it at sign-in); src/dolphin_system.rs start_tray.
  await bind.mainSetCommon(key: 'dolphin-tray-start', value: '');
  await windowManager.hide();
  return true;
}
