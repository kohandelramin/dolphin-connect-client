import 'dart:async';

import 'package:flutter/material.dart';

import '../models/platform_model.dart';
import 'switches.dart';
import 'theme.dart';

/// DD-34 «شروع / توقف اشتراک»: "Y" while the customer has stopped sharing. Read by the server process, which then
/// refuses every connection before any login (src/server/connection.rs `on_open`, src/dolphin_system_core.rs), and sent
/// on the heartbeat as `dolphin_share`.
const kDolphinShareOffOption = 'dolphin-share-off';

/// The control shows unless the portal's `share-toggle` switch hides it («اجباری» shows it too: there is nothing to
/// force on, the customer may still stop).
bool shareControlShown(SwitchMode shareToggle) => shareToggle != SwitchMode.hidden;

/// Same rule as `sharing_stopped` in src/dolphin_system_core.rs: an old "Y" counts only while the control exists.
bool sharingStopped(SwitchMode shareToggle, String option) => shareControlShown(shareToggle) && option == 'Y';

/// The option to write when the button is pressed.
String shareToggleValue(bool stoppedNow) => stoppedNow ? '' : 'Y';

const kShareOnLabel = 'اشتراک روشن است';
const kShareOnHint = 'کارشناس دلفین با اجازه‌ی پورتال می‌تواند وصل شود.';
const kShareStop = 'توقف اشتراک';
const kShareOffLabel = 'اشتراک متوقف است';
const kShareOffHint = 'هیچ کس نمی‌تواند وصل شود، حتی کارشناس دلفین.';
const kShareStart = 'شروع اشتراک';

/// The strip on the home screen. Pure: [onToggle] does the work.
class DolphinShareView extends StatelessWidget {
  final bool stopped;
  final VoidCallback onToggle;
  const DolphinShareView({super.key, required this.stopped, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final fg = stopped ? DolphinColors.dangerText : DolphinColors.aquaText;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: stopped ? kShareOffLabel : kShareOnLabel,
        child: Container(
          key: const ValueKey('dolphin-share'),
          padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 8, 6),
          decoration: BoxDecoration(
            color: stopped ? DolphinColors.dangerSoft : DolphinColors.aquaSoft,
            border: Border(bottom: BorderSide(color: stopped ? DolphinColors.danger : DolphinColors.line)),
          ),
          child: Row(children: [
            Icon(stopped ? Icons.block : Icons.wifi_tethering, color: fg, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(stopped ? kShareOffLabel : kShareOnLabel,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5)),
                Text(stopped ? kShareOffHint : kShareOnHint,
                    style: const TextStyle(color: DolphinColors.muted, fontSize: 11, height: 1.4)),
              ]),
            ),
            const SizedBox(width: 6),
            stopped
                ? FilledButton(
                    key: const ValueKey('dolphin-share-toggle'),
                    onPressed: onToggle,
                    style: FilledButton.styleFrom(
                        backgroundColor: DolphinColors.azure,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact),
                    child: const Text(kShareStart),
                  )
                : OutlinedButton(
                    key: const ValueKey('dolphin-share-toggle'),
                    onPressed: onToggle,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: DolphinColors.dangerText, visualDensity: VisualDensity.compact),
                    child: const Text(kShareStop),
                  ),
          ]),
        ),
      ),
    );
  }
}

// Each start of the app shares again: opening Dolphin Connect is the customer's consent (ADR-0015), and a stop
// forgotten from an earlier day must not lock out the next call. Writes go through `main_set_common` to
// src/dolphin_system.rs, which reads the server's options right before it writes one key: upstream's `mainSetOption`
// would send the window's cached copy of every option and could put back a value the portal had just changed.
bool _resetThisRun = false;

/// What the strip shows: the customer's press until the server's option agrees (or 5 s passed), then the option.
bool shareShownStopped({required bool read, bool? pending, Duration? sincePress}) {
  if (pending == null || sincePress == null || sincePress > const Duration(seconds: 5)) return read;
  return pending;
}

/// The strip with its state: the switch and the option read every 2 s; nothing when the switch hides it.
class DolphinShareControl extends StatefulWidget {
  const DolphinShareControl({super.key});

  @override
  State<DolphinShareControl> createState() => _DolphinShareControlState();
}

class _DolphinShareControlState extends State<DolphinShareControl> {
  Timer? _timer;
  SwitchMode _mode = SwitchMode.hidden;
  bool _stopped = false;
  bool? _pending;
  DateTime? _pressedAt;

  @override
  void initState() {
    super.initState();
    if (!_resetThisRun) {
      _resetThisRun = true;
      bind.mainSetCommon(key: 'dolphin-share-reset', value: '');
    }
    _read();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _read() {
    final mode = DolphinSwitches.parse(bind.mainGetOptionSync(key: kDolphinSwitchesOption)).mode(DolphinSwitch.shareToggle);
    final read = sharingStopped(mode, bind.mainGetOptionSync(key: kDolphinShareOffOption));
    final since = _pressedAt == null ? null : DateTime.now().difference(_pressedAt!);
    final stopped = shareShownStopped(read: read, pending: _pending, sincePress: since);
    if (_pending != null && (read == _pending || stopped == read)) _pending = null;
    if (mounted && (mode != _mode || stopped != _stopped)) {
      setState(() {
        _mode = mode;
        _stopped = stopped;
      });
    }
  }

  Future<void> _toggle() async {
    final next = shareToggleValue(_stopped);
    _pending = next == 'Y';
    _pressedAt = DateTime.now();
    setState(() => _stopped = _pending!);
    await bind.mainSetCommon(key: 'dolphin-share-off', value: next);
  }

  @override
  Widget build(BuildContext context) {
    if (!shareControlShown(_mode)) return const SizedBox.shrink();
    return DolphinShareView(stopped: _stopped, onToggle: _toggle);
  }
}
