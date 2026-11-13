import 'package:flutter/material.dart';

import '../brand.dart';
import '../digits.dart';
import '../tech/state.dart' show PcViewMode;
import '../tech_theme.dart' show themeModeLabel;
import 'settings_model.dart';
import 'widgets.dart';

/// Plan 19 (T6): the technician app's settings in sections, each with a one-line subtitle and «بازنشانی این بخش».
/// Plain words, no codec names; the picture quality is shown, not changed (DD-3).
const kSupportPhone = '021-44280505';
const kResetSection = 'بازنشانی این بخش';

class TechSettingsView extends StatefulWidget {
  final TechSettingsModel model;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeMode;
  final PcViewMode viewMode;
  final ValueChanged<PcViewMode> onViewMode;
  final bool toasts;
  final ValueChanged<bool> onToasts;
  final String downloadsPath;
  final VoidCallback? onOpenDownloads;
  final String portalUrl;
  final bool? serverOnline;
  final bool portalReachable;
  final String version;

  /// «بررسی نسخه‌ی تازه» (the app's DolphinUpdateCheckButton; a placeholder in tests).
  final Widget? updateButton;
  final TechSettingsSection initial;

  const TechSettingsView({
    super.key,
    required this.model,
    required this.themeMode,
    required this.onThemeMode,
    required this.viewMode,
    required this.onViewMode,
    required this.toasts,
    required this.onToasts,
    this.downloadsPath = '',
    this.onOpenDownloads,
    this.portalUrl = '',
    this.serverOnline,
    this.portalReachable = true,
    this.version = '',
    this.updateButton,
    this.initial = TechSettingsSection.display,
  });

  @override
  State<TechSettingsView> createState() => _TechSettingsViewState();
}

class _TechSettingsViewState extends State<TechSettingsView> {
  late TechSettingsSection _section = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 170,
        decoration: BoxDecoration(color: t.surface, border: BorderDirectional(end: BorderSide(color: t.line))),
        padding: const EdgeInsets.all(8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final s in TechSettingsSection.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: s == _section ? t.surfaceAlt : Colors.transparent,
                borderRadius: BorderRadius.circular(t.radiusSmall),
                child: InkWell(
                  key: ValueKey('settings-${s.name}'),
                  borderRadius: BorderRadius.circular(t.radiusSmall),
                  onTap: () => setState(() => _section = s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    child: Text(sectionTitle(s),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: s == _section ? t.primaryText : t.text)),
                  ),
                ),
              ),
            ),
        ]),
      ),
      Expanded(
        child: ListenableBuilder(
          listenable: widget.model,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(sectionTitle(_section), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.text)),
              const SizedBox(height: 2),
              TechHint(sectionSubtitle(_section)),
              const SizedBox(height: 12),
              ..._rows(context),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TechButton(kResetSection,
                    key: const ValueKey('settings-reset'), icon: Icons.restart_alt, onPressed: _reset),
              ),
            ],
          ),
        ),
      ),
    ]);
  }

  Future<void> _reset() async {
    switch (_section) {
      case TechSettingsSection.look:
        widget.onThemeMode(ThemeMode.system);
        widget.onViewMode(PcViewMode.tiles);
      case TechSettingsSection.sound:
        widget.onToasts(true);
      default:
        await widget.model.reset(_section);
    }
    if (mounted) setState(() {});
  }

  List<Widget> _rows(BuildContext context) {
    final m = widget.model;
    switch (_section) {
      case TechSettingsSection.display:
        return [
          _box(context, 'کیفیت تصویر', [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final q in kQualityChoices) TechChip(qualityLabel(q), selected: _qualityKey(m.quality) == q),
              if (m.quality == 'custom') TechChip(qualityLabel('custom'), selected: true),
            ]),
            const SizedBox(height: 6),
            const TechHint(kQualityNote),
          ]),
          const SizedBox(height: 10),
          _box(context, 'اندازه‌ی تصویر در پنجره', [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (v, l) in kViewStyles)
                TechChip(l, key: ValueKey('view-style-$v'), selected: m.viewStyle == v, onTap: () => m.setViewStyle(v)),
            ]),
          ]),
          const SizedBox(height: 10),
          _box(context, 'جابه‌جایی تصویر بزرگ‌تر از پنجره', [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (v, l) in kScrollStyles)
                TechChip(l, key: ValueKey('scroll-style-$v'), selected: m.scrollStyle == v, onTap: () => m.setScrollStyle(v)),
            ]),
          ]),
          const SizedBox(height: 6),
          for (final s in kDisplaySwitches) _switch(context, s.label, m.isOn(s), (v) => m.setSwitch(s, v), s.key),
        ];
      case TechSettingsSection.look:
        return [
          _box(context, 'رنگ برنامه', [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final mode in const [ThemeMode.system, ThemeMode.light, ThemeMode.dark])
                TechChip(themeModeLabel(mode),
                    key: ValueKey('theme-${mode.name}'),
                    selected: widget.themeMode == mode,
                    onTap: () => widget.onThemeMode(mode)),
            ]),
          ]),
          const SizedBox(height: 10),
          _box(context, 'نمای رایانه‌ها', [
            Wrap(spacing: 6, runSpacing: 6, children: [
              TechChip('کاشی', selected: widget.viewMode == PcViewMode.tiles, onTap: () => widget.onViewMode(PcViewMode.tiles)),
              TechChip('فهرست', selected: widget.viewMode == PcViewMode.list, onTap: () => widget.onViewMode(PcViewMode.list)),
            ]),
          ]),
        ];
      case TechSettingsSection.input:
        return [for (final s in kInputSwitches) _switch(context, s.label, m.isOn(s), (v) => m.setSwitch(s, v), s.key)];
      case TechSettingsSection.files:
        return [
          _box(context, 'فایل‌های «فرستاده‌ی مشتری»', [
            Text(widget.downloadsPath.isEmpty ? '…' : widget.downloadsPath,
                textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12.5, color: tokensOf(context).text)),
            const SizedBox(height: 6),
            if (widget.onOpenDownloads != null) TechButton('باز کردن پوشه', icon: Icons.folder_open, onPressed: widget.onOpenDownloads),
          ]),
          const SizedBox(height: 8),
          const TechHint('فایل‌هایی که در جلسه به رایانه‌ی مشتری می‌فرستید، از پنجره‌ی «فایل‌ها»ی همان جلسه انتخاب می‌شوند.'),
        ];
      case TechSettingsSection.sound:
        return [
          _switch(context, 'اعلان ویندوز (با صدا) برای درخواست و تماس تازه، وقتی برنامه جلوی چشم نیست', widget.toasts,
              widget.onToasts, 'toasts'),
        ];
      case TechSettingsSection.network:
        final t = tokensOf(context);
        return [
          _info(context, 'سرور دلفین',
              widget.serverOnline == null ? 'در حال بررسی…' : (widget.serverOnline! ? 'وصل' : 'وصل نیست'),
              widget.serverOnline == false ? t.warning : null),
          _info(context, 'پورتال دلفین', widget.portalReachable ? 'در دسترس' : 'در دسترس نیست',
              widget.portalReachable ? null : t.warning),
          _info(context, 'نشانی پورتال', widget.portalUrl, null, ltr: true),
          const SizedBox(height: 8),
          const TechHint('تنظیم سرور و مسیر اتصال در این برنامه ثابت است و تغییر نمی‌کند.'),
        ];
      case TechSettingsSection.about:
        return [
          _info(context, 'برنامه', DolphinBrand.technicianNameFa, null),
          _info(context, 'نسخه', faDigits(widget.version), null),
          _info(context, 'پشتیبانی دلفین', faDigits(kSupportPhone), null, ltr: true),
          const SizedBox(height: 10),
          if (widget.updateButton != null) widget.updateButton!,
        ];
    }
  }

  String _qualityKey(String q) => kQualityChoices.contains(q) ? q : (q == 'custom' ? '' : 'balanced');

  Widget _box(BuildContext context, String title, List<Widget> children) => TechPanel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: tokensOf(context).text)),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Widget _switch(BuildContext context, String label, bool on, ValueChanged<bool> onChanged, String key) {
    final t = tokensOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: t.text, height: 1.6))),
        Switch(
          key: ValueKey('switch-$key'),
          value: on,
          activeColor: t.onPrimary,
          activeTrackColor: t.primary,
          inactiveThumbColor: t.textMuted,
          inactiveTrackColor: t.lineStrong,
          onChanged: onChanged,
        ),
      ]),
    );
  }

  Widget _info(BuildContext context, String label, String value, Color? color, {bool ltr = false}) {
    final t = tokensOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 13, color: t.textMuted))),
        Expanded(
          child: Text(value,
              textDirection: ltr ? TextDirection.ltr : null,
              textAlign: ltr ? TextAlign.right : TextAlign.start,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color ?? t.text)),
        ),
      ]),
    );
  }
}
