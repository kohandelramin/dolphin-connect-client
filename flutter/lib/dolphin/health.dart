import 'digits.dart';

/// DD-38 «بررسی سلامت», DD-19 the stopped service, DD-40 a PC with no monitor: the rules and the Persian texts. Pure:
/// the probes (health_probe.dart) bring the facts in.

/// The Windows service's state (SERVICE_STATUS.dwCurrentState), or what stood in the way of reading it.
enum ServiceState { running, stopped, pending, missing, unknown }

/// SERVICE_STATUS.dwCurrentState → our state: 4 running; 1 stopped, 7 paused; 2, 3, 5, 6 on the way.
ServiceState serviceStateFrom(int currentState) => switch (currentState) {
      4 => ServiceState.running,
      1 || 7 => ServiceState.stopped,
      2 || 3 || 5 || 6 => ServiceState.pending,
      _ => ServiceState.unknown,
    };

/// ERROR_SERVICE_DOES_NOT_EXIST when OpenService failed; any other error (access denied …) is unknown.
ServiceState serviceStateFromError(int error) => error == 1060 ? ServiceState.missing : ServiceState.unknown;

/// DD-19: the installed app's service should run and does not. Not for a portable app (no service), not while the
/// customer turned it off on purpose (`stop-service`, BL-SVC already shows that), not while it is starting or
/// stopping, and not when Windows would not say.
bool serviceDown({required bool installed, required ServiceState state, required bool stopOption}) =>
    installed && !stopOption && (state == ServiceState.stopped || state == ServiceState.missing);

/// DD-19: the notice shows after two reads in a row said "down", so a restart by an update or an install (a few
/// seconds) never flashes it.
class ServiceWatch {
  int _downReads = 0;
  bool get down => _downReads >= 2;

  /// Notes one read; true when what [down] says changed.
  bool note(bool downNow) {
    final before = down;
    _downReads = downNow ? _downReads + 1 : 0;
    return before != down;
  }
}

/// Same idea as upstream's `no_displays` (src/server/display_service.rs, DUMMY_DISPLAY_SIDE_MAX_SIZE 1024): no screen
/// at all, or one small one (Windows' stand-in when no monitor is plugged in). [screens]: (width, height) in physical
/// pixels.
bool looksHeadless(List<(double, double)> screens) {
  if (screens.isEmpty) return true;
  if (screens.length > 1) return false;
  final (w, h) = screens.first;
  return w <= 1024 && h <= 1024;
}

/// Windows 10 2004 (build 19041) and later can take upstream's virtual display (src/virtual_display_manager.rs
/// `is_virtual_display_supported`).
const kVirtualDisplayMinBuild = 19041;

const kHeadlessTitle = 'این رایانه صفحه‌نمایش ندارد';

/// DD-40: what to do on a PC with no monitor, by what it can do. Display only: nothing is installed from here.
String headlessFix({required bool installed, required int windowsBuild}) {
  if (windowsBuild > 0 && windowsBuild < kVirtualDisplayMinBuild) {
    return 'تا کارشناس تصویر ببیند، یک صفحه‌نمایش یا «دامی پلاگ HDMI» به رایانه وصل کنید.';
  }
  if (!installed) {
    return 'برنامه را نصب کنید تا هنگام اتصال یک صفحه‌نمایش مجازی بسازد؛ یا یک «دامی پلاگ HDMI» وصل کنید.';
  }
  return 'برنامه هنگام اتصال یک صفحه‌نمایش مجازی می‌سازد؛ اگر کارشناس تصویر ندید، یک «دامی پلاگ HDMI» وصل کنید.';
}

enum CheckTone { ok, warn, bad, info }

/// The safe repairs. Only the service has one: upstream's own start (UAC prompt).
enum HealthFix { none, startService }

/// One line of «بررسی سلامت».
class HealthItem {
  final String title;
  final String result;
  final CheckTone tone;
  final HealthFix fix;
  const HealthItem(this.title, this.result, this.tone, {this.fix = HealthFix.none});

  String get line => '$title: $result';

  @override
  String toString() => line;
}

const kFixServiceLabel = 'تعمیر سرویس';

HealthItem serviceItem({required bool installed, required ServiceState state, required bool stopOption}) {
  const t = 'سرویس دلفین';
  if (!installed) return const HealthItem(t, 'این نسخه نصب نشده و سرویس ندارد؛ تا پنجره باز است کار می‌کند.', CheckTone.info);
  if (stopOption) return const HealthItem(t, 'خاموش شده است.', CheckTone.bad, fix: HealthFix.startService);
  return switch (state) {
    ServiceState.running => const HealthItem(t, 'روشن است.', CheckTone.ok),
    ServiceState.pending => const HealthItem(t, 'در حال روشن یا خاموش شدن است.', CheckTone.warn),
    ServiceState.stopped => const HealthItem(t, 'خاموش است.', CheckTone.bad, fix: HealthFix.startService),
    ServiceState.missing => const HealthItem(t, 'پیدا نشد.', CheckTone.bad, fix: HealthFix.startService),
    ServiceState.unknown => const HealthItem(t, 'ویندوز وضعیت آن را نگفت.', CheckTone.warn),
  };
}

/// Registered with the rendezvous server (the same status the home bar shows).
HealthItem registeredItem(bool registered) => registered
    ? const HealthItem('ثبت در سرور دلفین', 'ثبت شده است.', CheckTone.ok)
    : const HealthItem('ثبت در سرور دلفین', 'هنوز ثبت نشده است.', CheckTone.bad);

/// DNS: [addresses] null when the lookup failed; a host that is already an IP needs no lookup.
HealthItem dnsItem(String host, {required bool isIp, List<String>? addresses}) {
  const t = 'پیدا کردن نشانی سرور (DNS)';
  if (host.isEmpty) return const HealthItem(t, 'نشانی سرور در برنامه نیست.', CheckTone.bad);
  if (isIp) return const HealthItem(t, 'نشانی عددی است؛ لازم نیست.', CheckTone.info);
  if (addresses == null || addresses.isEmpty) {
    return const HealthItem(t, 'پیدا نشد؛ اینترنت یا DNS را بررسی کنید (VPN را خاموش و روشن کنید).', CheckTone.bad);
  }
  return HealthItem(t, 'پیدا شد (${faDigits(addresses.first)}).', CheckTone.ok);
}

/// A TCP connect to one of Dolphin's ports (rendezvous 21116, relay 21117, the portal).
HealthItem portItem(String title, int port, bool reached) => reached
    ? HealthItem(title, 'در دسترس است (درگاه ${faDigits('$port')}).', CheckTone.ok)
    : HealthItem(title, 'در دسترس نیست (درگاه ${faDigits('$port')})؛ فایروال، مودم یا VPN جلوی آن را گرفته است.', CheckTone.bad);

/// Writing a small file in the app's folders: [failed] are the folders that refused.
HealthItem diskItem(List<String> failed) => failed.isEmpty
    ? const HealthItem('نوشتن روی دیسک', 'پوشه‌های برنامه نوشتنی‌اند.', CheckTone.ok)
    : HealthItem('نوشتن روی دیسک', 'نوشتن نشد (${failed.join('، ')})؛ جای خالی دیسک یا آنتی‌ویروس را بررسی کنید.', CheckTone.bad);

/// DD-40 inside the check list.
HealthItem displayItem({required bool headless, required bool installed, required int windowsBuild}) => headless
    ? HealthItem('صفحه‌نمایش', '$kHeadlessTitle. ${headlessFix(installed: installed, windowsBuild: windowsBuild)}', CheckTone.warn)
    : const HealthItem('صفحه‌نمایش', 'وصل است.', CheckTone.ok);

/// The first line of the list: all good, or how many need a look.
String healthSummary(List<HealthItem> items) {
  final bad = items.where((i) => i.tone == CheckTone.bad).length;
  final warn = items.where((i) => i.tone == CheckTone.warn).length;
  if (bad == 0 && warn == 0) return 'همه چیز درست است.';
  if (bad == 0) return '${faDigits('$warn')} مورد را ببینید.';
  return '${faDigits('$bad')} مورد مشکل دارد.';
}

/// «ذخیره‌ی گزارش»'s file name on the desktop.
String healthReportName(DateTime t) =>
    'dolphin-health-${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}-'
    '${t.hour.toString().padLeft(2, '0')}${t.minute.toString().padLeft(2, '0')}.txt';
