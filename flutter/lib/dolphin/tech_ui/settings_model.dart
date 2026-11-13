import 'package:flutter/material.dart';

import 'platform.dart';

/// Plan 19 (T6, RO-10): the technician app's settings, in sections. The keys are upstream's own (flutter/lib/consts.dart),
/// so the session windows behave exactly as upstream's settings page would make them; written here as literals to keep
/// this file free of the app's bridge. Nothing here changes how a session connects: the picture quality is shown in
/// plain words only (DD-3 decides any change).
const kViewStyleKey = 'view_style'; // kOptionViewStyle
const kScrollStyleKey = 'scroll_style'; // kOptionScrollStyle
const kImageQualityKey = 'image_quality'; // kOptionImageQuality (read only here)
const kZoomCursorKey = 'zoom-cursor'; // kOptionZoomCursor
const kQualityMonitorKey = 'show_quality_monitor'; // kOptionShowQualityMonitor
const kSeparateWindowsKey = 'displays_as_individual_windows'; // kKeyShowDisplaysAsIndividualWindows
const kSwapMouseKey = 'swap-left-right-mouse'; // kOptionSwapLeftRightMouse
const kReverseWheelKey = 'reverse_mouse_wheel'; // kKeyReverseMouseWheel
const kOpenInTabsKey = 'enable-open-new-connections-in-tabs'; // kOptionOpenNewConnInTabs (local)

/// The app's own (Prefs) keys.
const kTechToastsPref = 'dolphin-tech-toasts';

enum TechSettingsSection { display, look, input, files, sound, network, about }

String sectionTitle(TechSettingsSection s) => switch (s) {
      TechSettingsSection.display => 'نمایش',
      TechSettingsSection.look => 'ظاهر',
      TechSettingsSection.input => 'صفحه‌کلید و ماوس',
      TechSettingsSection.files => 'فایل و پوشه‌ها',
      TechSettingsSection.sound => 'صدا',
      TechSettingsSection.network => 'شبکه',
      TechSettingsSection.about => 'درباره',
    };

String sectionSubtitle(TechSettingsSection s) => switch (s) {
      TechSettingsSection.display => 'کیفیت تصویر، اندازه و رفتار پنجره‌ی جلسه.',
      TechSettingsSection.look => 'روشن، تیره یا مثل ویندوز؛ و نمای پیش‌فرض رایانه‌ها.',
      TechSettingsSection.input => 'دکمه‌های ماوس و جهت چرخ ماوس در جلسه.',
      TechSettingsSection.files => 'جای فایل‌هایی که مشتری برای شما می‌فرستد.',
      TechSettingsSection.sound => 'اعلان ویندوز و صدای آن برای درخواست‌های تازه.',
      TechSettingsSection.network => 'وضعیت سرور دلفین و پورتال؛ فقط برای دیدن.',
      TechSettingsSection.about => 'نسخه‌ی برنامه، به‌روزرسانی و تماس با پشتیبانی.',
    };

/// Plain words for upstream's picture quality (display only).
String qualityLabel(String v) => switch (v) {
      'best' => 'بهترین کیفیت',
      'low' => 'روان‌تر روی اینترنت ضعیف',
      'custom' => 'سفارشی',
      _ => 'خودکار (پیشنهادی)',
    };

const kQualityChoices = ['balanced', 'best', 'low'];
const kQualityNote = '«خودکار» کیفیت را با سرعت اینترنت مشتری تنظیم می‌کند. این بخش فعلاً فقط نشان می‌دهد؛ تغییر آن پس از سنجش انجام می‌شود.';

const kViewStyles = [('original', 'اندازه‌ی اصلی'), ('adaptive', 'جا شدن در پنجره')];
const kScrollStyles = [('scrollauto', 'خودکار با ماوس'), ('scrollbar', 'نوار پیمایش'), ('scrolledge', 'در لبه‌ها')];

/// One on/off row: label, upstream key, and whether it is a local option (true) or a user default (false).
class SettingSwitch {
  final String label;
  final String key;
  final bool local;
  final bool defaultOn;
  const SettingSwitch(this.label, this.key, {this.local = false, this.defaultOn = false});
}

const kDisplaySwitches = [
  SettingSwitch('نشانگر ماوس با بزرگ‌نمایی تصویر بزرگ شود', kZoomCursorKey),
  SettingSwitch('کیفیت اتصال روی تصویر نشان داده شود', kQualityMonitorKey),
  SettingSwitch('هر صفحه‌ی مشتری در پنجره‌ی جدا', kSeparateWindowsKey),
  SettingSwitch('جلسه‌ها در زبانه‌های یک پنجره', kOpenInTabsKey, local: true),
];

const kInputSwitches = [
  SettingSwitch('جای دکمه‌ی چپ و راست ماوس عوض شود', kSwapMouseKey),
  SettingSwitch('جهت چرخ ماوس برعکس شود', kReverseWheelKey),
];

/// Reads and writes the sections' values. [ChangeNotifier] so the page redraws after a change or a reset.
class TechSettingsModel extends ChangeNotifier {
  final TechSettingsStore store;
  TechSettingsModel(this.store);

  String get quality => store.userDefault(kImageQualityKey);
  String get viewStyle => store.userDefault(kViewStyleKey).isEmpty ? 'original' : store.userDefault(kViewStyleKey);
  String get scrollStyle =>
      store.userDefault(kScrollStyleKey).isEmpty ? 'scrollauto' : store.userDefault(kScrollStyleKey);

  bool isOn(SettingSwitch s) => s.local ? store.localBool(s.key) : store.userDefault(s.key) == 'Y';

  Future<void> setSwitch(SettingSwitch s, bool on) async {
    if (s.local) {
      await store.setLocalBool(s.key, on);
    } else {
      await store.setUserDefault(s.key, on ? 'Y' : store.no);
    }
    notifyListeners();
  }

  Future<void> setViewStyle(String v) async {
    await store.setUserDefault(kViewStyleKey, v);
    notifyListeners();
  }

  Future<void> setScrollStyle(String v) async {
    await store.setUserDefault(kScrollStyleKey, v);
    notifyListeners();
  }

  /// «بازنشانی این بخش»: upstream's defaults for the section's own options (the theme and view mode are reset by the
  /// page itself, which owns them).
  Future<void> reset(TechSettingsSection s) async {
    switch (s) {
      case TechSettingsSection.display:
        await store.setUserDefault(kViewStyleKey, 'original');
        await store.setUserDefault(kScrollStyleKey, 'scrollauto');
        for (final sw in kDisplaySwitches) {
          await (sw.local ? store.setLocalBool(sw.key, sw.defaultOn) : store.setUserDefault(sw.key, sw.defaultOn ? 'Y' : store.no));
        }
      case TechSettingsSection.input:
        for (final sw in kInputSwitches) {
          await store.setUserDefault(sw.key, sw.defaultOn ? 'Y' : store.no);
        }
      default:
        break;
    }
    notifyListeners();
  }
}
