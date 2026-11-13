import 'package:flutter/material.dart';

import '../tech/api.dart';
import '../theme.dart' show kDolphinFont;
import '../theme_tokens.dart';

/// Plan 19: the small pieces every native technician screen shares. Every colour and radius comes from the tokens in
/// use for the app's brightness ([tokensOf]); nothing here has a colour of its own except white on a filled colour.

/// The tokens of the theme around [context] (light or dark, as the technician chose; DD-53).
DolphinThemeTokens tokensOf(BuildContext context) => DolphinTheme.of(Theme.of(context).brightness);

/// What a PC's dot says. The shapes differ too (filled circle, diamond, ring, dashed ring), for colour-blind eyes.
enum PcState { online, busy, offline, unknown }

/// Online, in another technician's session, off, or unknown (a row from the offline list, TD-2).
PcState pcStateOf(Computer c) {
  if (c.fromCache) return PcState.unknown;
  final s = c.session;
  if (s != null && !s.mine) return PcState.busy;
  return c.online ? PcState.online : PcState.offline;
}

String pcStateLabel(PcState s) => switch (s) {
      PcState.online => 'در دسترس',
      PcState.busy => 'در جلسه',
      PcState.offline => 'خاموش',
      PcState.unknown => 'وضعیت نامعلوم',
    };

class TechDot extends StatelessWidget {
  final PcState state;
  final double size;
  const TechDot(this.state, {super.key, this.size = 10});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final Widget dot = switch (state) {
      PcState.online => Container(
          width: size, height: size, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
      PcState.busy => Transform.rotate(
          angle: 0.785398,
          child: Container(width: size * 0.82, height: size * 0.82, color: t.warning),
        ),
      PcState.offline => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.offlineDot, width: 2))),
      PcState.unknown => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
              shape: BoxShape.circle, border: Border.all(color: t.textMuted, width: 1.4, style: BorderStyle.solid)),
          child: Center(child: Container(width: size / 3, height: size / 3, color: t.textMuted)),
        ),
    };
    return Tooltip(message: pcStateLabel(state), child: SizedBox(width: size + 2, height: size + 2, child: Center(child: dot)));
  }
}

/// A pill: the filter chips, reason chips, tags. [selected] fills it with the primary colour (white text).
class TechChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool dropdown;
  final bool soft;
  const TechChip(this.label,
      {super.key, this.selected = false, this.onTap, this.icon, this.dropdown = false, this.soft = false});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final fg = selected ? t.onPrimary : (soft ? t.success : t.text);
    final bg = selected ? t.primary : (soft ? t.accentSoft : t.surfaceAlt);
    final body = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 12, color: fg, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
        if (dropdown) ...[const SizedBox(width: 2), Icon(Icons.arrow_drop_down, size: 16, color: fg)],
      ]),
    );
    if (onTap == null) return body;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(borderRadius: BorderRadius.circular(99), onTap: onTap, child: body),
    );
  }
}

enum TechButtonKind { primary, outline, danger, quiet }

/// The dense button of lists, tiles and the card (32 px; the app's 44 px buttons are for dialogs and forms).
class TechButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final TechButtonKind kind;
  final IconData? icon;
  final bool expand;
  const TechButton(this.label,
      {super.key, required this.onPressed, this.kind = TechButtonKind.outline, this.icon, this.expand = false});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusSmall));
    const padding = EdgeInsets.symmetric(horizontal: 12);
    const size = Size(0, 32);
    const text = TextStyle(fontFamily: kDolphinFont, fontSize: 12.5, fontWeight: FontWeight.w700);
    final child = icon == null
        ? Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)
        : label.isEmpty
            ? Icon(icon, size: 17)
            : Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15),
            const SizedBox(width: 4),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]);
    final Widget b = switch (kind) {
      TechButtonKind.primary => FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
              minimumSize: size,
              padding: padding,
              shape: shape,
              textStyle: text,
              backgroundColor: t.primary,
              foregroundColor: t.onPrimary,
              disabledBackgroundColor: t.surfaceAlt,
              disabledForegroundColor: t.textMuted),
          child: child),
      TechButtonKind.danger => FilledButton(
          onPressed: onPressed,
          style: FilledButton.styleFrom(
              minimumSize: size,
              padding: padding,
              shape: shape,
              textStyle: text,
              backgroundColor: t.dangerFill,
              foregroundColor: t.onPrimary,
              disabledBackgroundColor: t.surfaceAlt,
              disabledForegroundColor: t.textMuted),
          child: child),
      TechButtonKind.outline => OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
              minimumSize: size,
              padding: padding,
              shape: shape,
              textStyle: text,
              foregroundColor: t.text,
              backgroundColor: t.surface,
              disabledForegroundColor: t.textMuted,
              side: BorderSide(color: t.lineStrong)),
          child: child),
      TechButtonKind.quiet => TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
              minimumSize: size, padding: padding, shape: shape, textStyle: text, foregroundColor: t.primaryText),
          child: child),
    };
    return expand ? SizedBox(width: double.infinity, child: b) : b;
  }
}

/// The unread count on the bell, the waiting requests in the navigation.
class TechBadge extends StatelessWidget {
  final int count;
  const TechBadge(this.count, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: t.dangerFill, borderRadius: BorderRadius.circular(99)),
      child: Text(count > 99 ? '۹۹+' : _fa(count),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: t.onPrimary)),
    );
  }
}

String _fa(int n) => n.toString().replaceAllMapped(RegExp(r'[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);

/// A card on the window's ground: surface, hairline, the control radius.
class TechPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? border;
  const TechPanel({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.color, this.border});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return DecoratedBox(
      decoration: BoxDecoration(
          color: color ?? t.surface,
          border: Border.all(color: border ?? t.line),
          borderRadius: BorderRadius.circular(t.radius)),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// One muted line under a title.
class TechHint extends StatelessWidget {
  final String text;
  final int? maxLines;
  final Color? color;
  const TechHint(this.text, {super.key, this.maxLines, this.color});

  @override
  Widget build(BuildContext context) => Text(text,
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12, color: color ?? tokensOf(context).textMuted, height: 1.6));
}

/// The Windows mark on a tile: four panes.
class WindowsMark extends StatelessWidget {
  final double size;
  final Color color;
  const WindowsMark({super.key, this.size = 22, required this.color});

  @override
  Widget build(BuildContext context) {
    final pane = size * 0.46;
    final gap = size - pane * 2;
    Widget p() => Container(width: pane, height: pane, color: color);
    return SizedBox(
      width: size,
      height: size,
      child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [p(), SizedBox(width: gap), p()]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [p(), SizedBox(width: gap), p()]),
      ]),
    );
  }
}

/// The organization's colour as a tile fill, darkened (never lightened) until white text on it reaches AA (4.5:1),
/// so any colour the portal gives keeps the PC name readable.
Color tileColorFor(int argb) {
  var c = Color(argb | 0xFF000000);
  for (var i = 0; i < 20 && contrastRatio(Colors.white, c) < kDolphinMinContrast; i++) {
    c = Color.lerp(c, Colors.black, 0.12)!;
  }
  return c;
}

/// The amber notice (T5 and other warnings): warning text on its soft fill.
class TechNotice extends StatelessWidget {
  final String text;
  final bool ok;
  final VoidCallback? onClose;
  const TechNotice(this.text, {super.key, this.ok = false, this.onClose});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final fg = ok ? t.success : t.warning;
    return Container(
      key: const ValueKey('tech-notice'),
      padding: const EdgeInsetsDirectional.only(start: 12, end: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
          color: ok ? t.accentSoft : t.warningSoft, borderRadius: BorderRadius.circular(t.radiusSmall)),
      child: Row(children: [
        Icon(ok ? Icons.check_circle_outline : Icons.info_outline, size: 16, color: fg),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: fg, height: 1.6))),
        if (onClose != null)
          IconButton(
              tooltip: 'بستن',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              icon: Icon(Icons.close, color: fg),
              onPressed: onClose),
      ]),
    );
  }
}

/// Loading, empty and error states of a list, centred in its area.
class TechEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? action;
  final VoidCallback? onAction;
  const TechEmpty({super.key, required this.icon, required this.text, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 36, color: t.textMuted),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: t.text, height: 1.7)),
          if (action != null && onAction != null) ...[
            const SizedBox(height: 10),
            TechButton(action!, onPressed: onAction),
          ],
        ]),
      ),
    );
  }
}

class TechLoading extends StatelessWidget {
  const TechLoading({super.key});
  @override
  Widget build(BuildContext context) =>
      Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: tokensOf(context).primary)));
}

/// A field in the technician's look: dense, the field radius, the strong line.
InputDecoration techField(BuildContext context, {String? hint, Widget? suffix, Widget? prefix}) {
  final t = tokensOf(context);
  final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(t.radiusField), borderSide: BorderSide(color: t.lineStrong));
  return InputDecoration(
    isDense: true,
    hintText: hint,
    hintStyle: TextStyle(color: t.textMuted, fontSize: 13),
    filled: true,
    fillColor: t.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(borderSide: BorderSide(color: t.primary, width: 1.5)),
    suffixIcon: suffix,
    prefixIcon: prefix,
  );
}

/// A small section heading inside a card.
class TechHeading extends StatelessWidget {
  final String text;
  final double size;
  const TechHeading(this.text, {super.key, this.size = 13.5});

  @override
  Widget build(BuildContext context) =>
      Text(text, style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: tokensOf(context).text));
}
