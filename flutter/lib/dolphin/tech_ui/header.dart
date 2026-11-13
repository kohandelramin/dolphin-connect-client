import 'package:flutter/material.dart';

import '../brand.dart';
import '../tech_theme.dart' show DolphinThemeSwitch;
import 'format.dart';
import 'widgets.dart';

/// Plan 19 (T1): the native window's top row: brand, own ID, search (Ctrl+K), the ID field with «اتصال» and
/// «ارائه دمو», the bell, «ظاهر» (DD-53), settings and the technician's name with «خروج».
const kSearchHint = 'جستجوی رایانه، سازمان، برچسب…';
const kIdFieldHint = 'شناسه‌ی رایانه';
const kConnectLabel = 'اتصال';
const kDemoLabel = 'ارائه دمو';
const kSignOutLabel = 'خروج';

class TechHeader extends StatelessWidget {
  final String myId;
  final String staffName;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ValueChanged<String> onSearch;
  final TextEditingController idField;
  final VoidCallback onConnect;
  final VoidCallback onDemo;
  final bool busy;
  final int unread;
  final VoidCallback onBell;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeMode;
  final VoidCallback onSettings;
  final VoidCallback onCopyId;
  final VoidCallback onSignOut;
  final GlobalKey? bellKey;

  const TechHeader({
    super.key,
    required this.myId,
    required this.staffName,
    required this.search,
    required this.searchFocus,
    required this.onSearch,
    required this.idField,
    required this.onConnect,
    required this.onDemo,
    this.busy = false,
    this.unread = 0,
    required this.onBell,
    required this.themeMode,
    required this.onThemeMode,
    required this.onSettings,
    required this.onCopyId,
    required this.onSignOut,
    this.bellKey,
  });

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      decoration: BoxDecoration(color: t.surface, border: Border(bottom: BorderSide(color: t.line))),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: t.primary, borderRadius: BorderRadius.circular(t.radiusTiny)),
          child: Icon(Icons.support_agent, size: 15, color: t.onPrimary),
        ),
        const SizedBox(width: 6),
        Text(DolphinBrand.technicianNameFa,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: t.primaryText)),
        const SizedBox(width: 10),
        Tooltip(
          message: 'کپی شناسه',
          child: InkWell(
            key: const ValueKey('tech-my-id'),
            borderRadius: BorderRadius.circular(99),
            onTap: myId.isEmpty ? null : onCopyId,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: BorderRadius.circular(99)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('شناسه‌ی من ', style: TextStyle(fontSize: 11, color: t.text)),
                Text(myId.isEmpty ? '…' : idFa(myId),
                    textDirection: TextDirection.ltr,
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.text)),
              ]),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            key: const ValueKey('tech-search'),
            controller: search,
            focusNode: searchFocus,
            onChanged: onSearch,
            style: TextStyle(fontSize: 13, color: t.text),
            decoration: techField(context,
                hint: kSearchHint,
                prefix: Icon(Icons.search, size: 18, color: t.textMuted),
                suffix: Center(
                  widthFactor: 1,
                  child: Container(
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                        border: Border.all(color: t.lineStrong), borderRadius: BorderRadius.circular(4)),
                    child: Text('Ctrl K',
                        textDirection: TextDirection.ltr, style: TextStyle(fontSize: 10, color: t.textMuted)),
                  ),
                )),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 124,
          child: TextField(
            key: const ValueKey('tech-id-field'),
            controller: idField,
            enabled: !busy,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 13, color: t.text),
            decoration: techField(context, hint: kIdFieldHint),
            onSubmitted: (_) => onConnect(),
          ),
        ),
        const SizedBox(width: 6),
        TechButton(kConnectLabel,
            key: const ValueKey('tech-connect'), kind: TechButtonKind.primary, onPressed: busy ? null : onConnect),
        const SizedBox(width: 6),
        TechButton(kDemoLabel, key: const ValueKey('tech-demo'), onPressed: busy ? null : onDemo),
        const SizedBox(width: 4),
        Stack(clipBehavior: Clip.none, children: [
          IconButton(
            key: bellKey ?? const ValueKey('tech-bell'),
            visualDensity: VisualDensity.compact,
            tooltip: 'اعلان‌ها',
            icon: Icon(Icons.notifications_none, color: t.textMuted, size: 20),
            onPressed: onBell,
          ),
          if (unread > 0) Positioned(top: 4, left: 4, child: IgnorePointer(child: TechBadge(unread))),
        ]),
        DolphinThemeSwitch(mode: themeMode, onChanged: onThemeMode),
        IconButton(
            key: const ValueKey('tech-settings'),
            visualDensity: VisualDensity.compact,
            tooltip: 'تنظیمات',
            icon: Icon(Icons.settings_outlined, color: t.textMuted, size: 20),
            onPressed: onSettings),
        PopupMenuButton<String>(
          key: const ValueKey('tech-staff-menu'),
          tooltip: 'حساب کارشناس',
          color: t.surface,
          onSelected: (v) {
            if (v == 'out') onSignOut();
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'out',
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Row(children: [
                  Icon(Icons.logout, size: 18, color: t.danger),
                  const SizedBox(width: 8),
                  Text(kSignOutLabel, style: TextStyle(color: t.text)),
                ]),
              ),
            ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: BorderRadius.circular(99)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.person_outline, size: 15, color: t.text),
              const SizedBox(width: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(staffName, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: t.text)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
