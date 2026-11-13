import 'package:flutter/material.dart';

import '../digits.dart';
import '../tech/actions.dart';
import '../tech/api.dart';
import '../tech/state.dart';
import 'format.dart';
import 'widgets.dart';

/// Plan 19 (T1): «رایانه‌ها»: the recent strip, the filters, and the PCs as tiles (the default, like DorsanDesk's
/// dashboard: a box in the organization's colour per PC, owner 2026-11-14, no screen images DD-27) or as a list. With
/// the portal away (T5) the same view shows the cached list read-only under the amber card.

/// What a PC row or tile can do; the shell routes each to the data layer.
class PcActions {
  final void Function(Computer pc) open;
  final void Function(Computer pc) connect;
  final void Function(Computer pc) demo;
  final void Function(Computer pc) favorite;
  final void Function(Computer pc) wake;
  final void Function(Computer pc) copyId;
  final bool busy;
  const PcActions(
      {required this.open,
      required this.connect,
      required this.demo,
      required this.favorite,
      required this.wake,
      required this.copyId,
      this.busy = false});
}

const kSortLabels = {
  PcSort.seen: 'آخرین تماس',
  PcSort.name: 'نام رایانه',
  PcSort.label: 'برچسب',
  PcSort.org: 'سازمان',
};

/// T5's line under the title: what is wrong, in the design's plain words (the title already says the portal is away).
String offlineCardText(OfflineReason? r) => switch (r) {
      OfflineReason.noInternet => 'اینترنت این رایانه وصل نیست؛ اتصال شبکه را بررسی کنید.',
      OfflineReason.slow => 'اینترنت این رایانه وصل است ولی پورتال دیر جواب می‌دهد.',
      _ => 'اینترنت این رایانه وصل است ولی پورتال جواب نمی‌دهد.',
    };

/// The portal's «پورتال دلفین در دسترس نیست» card (T5): the reason, the retry and what still works.
class TechOfflineCard extends StatelessWidget {
  final String reason;
  final VoidCallback onRetry;
  final DateTime? lastUpdated;
  const TechOfflineCard({super.key, required this.reason, required this.onRetry, this.lastUpdated});

  static const title = 'پورتال دلفین در دسترس نیست';
  static const retryEvery = 'هر ۱۵ ثانیه خودکار دوباره امتحان می‌شود.';
  static const byIdWorks = 'اتصال با شناسه کار می‌کند';

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Container(
        key: const ValueKey('tech-offline-card'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: t.warningSoft,
            border: Border.all(color: Color.lerp(t.warningSoft, t.warning, 0.35)!),
            borderRadius: BorderRadius.circular(t.radius)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: t.warning),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: t.warning)),
          ]),
          const SizedBox(height: 4),
          Text('$reason $retryEvery', style: TextStyle(fontSize: 12.5, height: 1.7, color: t.warning)),
          const SizedBox(height: 8),
          Row(children: [
            TechButton('تلاش دوباره', key: const ValueKey('tech-offline-retry'), icon: Icons.refresh, onPressed: onRetry),
            const SizedBox(width: 10),
            Icon(Icons.check, size: 15, color: t.warning),
            const SizedBox(width: 4),
            Text(byIdWorks, style: TextStyle(fontSize: 12.5, color: t.warning)),
          ]),
        ]),
      ),
      if (lastUpdated != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: TechHint('آخرین وضعیت: ساعت ${clockFa(lastUpdated!)} (فقط خواندنی)'),
        ),
    ]);
  }
}

/// «اخیر و علاقه‌مندی»: the app's last sessions, then the starred PCs, each one click away.
class TechRecentStrip extends StatelessWidget {
  final List<RecentPc> recent;
  final List<Computer> favorites;
  final PcActions actions;
  final void Function(String rustdeskId) connectId;

  /// The portal is away: states are unknown and «اتصال» opens without a call (TD-2).
  final bool offline;
  const TechRecentStrip(
      {super.key,
      required this.recent,
      required this.favorites,
      required this.actions,
      required this.connectId,
      this.offline = false});

  @override
  Widget build(BuildContext context) {
    final seen = <String>{};
    final chips = <Widget>[];
    for (final r in recent) {
      if (!seen.add(r.rustdeskId)) continue;
      chips.add(_chip(context, r.computer, r.rustdeskId, r.displayName));
    }
    for (final f in favorites) {
      if (chips.length >= 6) break;
      if (!seen.add(f.rustdeskId)) continue;
      chips.add(_chip(context, f, f.rustdeskId, f.displayName));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Row(children: [
      const TechHint('اخیر و علاقه‌مندی:'),
      const SizedBox(width: 6),
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [for (final c in chips) Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: c)]),
        ),
      ),
    ]);
  }

  Widget _chip(BuildContext context, Computer? pc, String rustdeskId, String name) {
    final t = tokensOf(context);
    final state = pc == null || offline ? PcState.unknown : pcStateOf(pc);
    final org = pc?.organization.name ?? '';
    final off = pc != null && state == PcState.offline;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: 10, end: 4, top: 3, bottom: 3),
      decoration: BoxDecoration(
          color: t.surface, border: Border.all(color: t.line), borderRadius: BorderRadius.circular(t.radiusSmall)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        TechDot(state, size: 9),
        const SizedBox(width: 6),
        InkWell(
          onTap: pc == null ? null : () => actions.open(pc),
          child: Text(org.isEmpty ? name : '$name · $org', style: TextStyle(fontSize: 12.5, color: t.text)),
        ),
        const SizedBox(width: 6),
        if (off)
          TechButton('روشن کن', onPressed: () => actions.wake(pc))
        else
          TechButton('اتصال',
              kind: TechButtonKind.primary,
              onPressed: actions.busy ? null : () => pc == null ? connectId(rustdeskId) : actions.connect(pc)),
      ]),
    );
  }
}

/// The filter row: همه / در دسترس N / ★ علاقه‌مندی / برچسب ▾ / سازمان ▾ / مرتب ▾, and فهرست / کاشی.
class TechFilterBar extends StatelessWidget {
  final DashboardController dash;
  const TechFilterBar({super.key, required this.dash});

  @override
  Widget build(BuildContext context) {
    final q = dash.query;
    final t = tokensOf(context);
    final orgs = <String, String>{};
    for (final c in dash.items) {
      if (c.organization.id.isNotEmpty) orgs[c.organization.id] = c.organization.name;
    }
    final tags = dash.tags;
    return Row(children: [
      Expanded(
        child: Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TechChip('همه', key: const ValueKey('filter-all'), selected: q.view == PcView.all, onTap: () => dash.setView(PcView.all)),
          TechChip(dash.offline ? 'در دسترس' : 'در دسترس ${faDigits('${dash.counts.online}')}',
              key: const ValueKey('filter-online'),
              selected: q.view == PcView.online,
              onTap: dash.offline ? null : () => dash.setView(PcView.online)),
          TechChip('علاقه‌مندی',
              key: const ValueKey('filter-favorite'),
              icon: Icons.star,
              selected: q.view == PcView.favorite,
              onTap: () => dash.setView(PcView.favorite)),
          _menu<String?>(
            context,
            key: const ValueKey('filter-tag'),
            label: q.tag == null ? 'برچسب' : 'برچسب: ${q.tag}',
            selected: q.tag != null,
            items: [(null, 'همه‌ی برچسب‌ها'), for (final tag in tags) (tag, tag)],
            onSelected: dash.setTag,
          ),
          _menu<String?>(
            context,
            key: const ValueKey('filter-org'),
            label: q.orgId == null ? 'سازمان' : 'سازمان: ${orgs[q.orgId] ?? '…'}',
            selected: q.orgId != null,
            enabled: !dash.offline,
            items: [(null, 'همه‌ی سازمان‌ها'), for (final e in orgs.entries) (e.key, e.value)],
            onSelected: dash.setOrganization,
          ),
          _menu<PcSort>(
            context,
            key: const ValueKey('filter-sort'),
            label: 'مرتب: ${kSortLabels[q.sort]}',
            enabled: !dash.offline,
            items: [for (final e in kSortLabels.entries) (e.key, e.value)],
            onSelected: (s) => dash.setSort(s),
          ),
        ]),
      ),
      const SizedBox(width: 8),
      Container(
        decoration: BoxDecoration(border: Border.all(color: t.line), borderRadius: BorderRadius.circular(t.radiusSmall)),
        padding: const EdgeInsets.all(2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _seg(context, 'فهرست', Icons.view_list, dash.viewMode == PcViewMode.list, () => dash.setViewMode(PcViewMode.list),
              const ValueKey('view-list')),
          _seg(context, 'کاشی', Icons.grid_view, dash.viewMode == PcViewMode.tiles, () => dash.setViewMode(PcViewMode.tiles),
              const ValueKey('view-tiles')),
        ]),
      ),
    ]);
  }

  Widget _seg(BuildContext context, String label, IconData icon, bool on, VoidCallback tap, Key key) {
    final t = tokensOf(context);
    return InkWell(
      key: key,
      onTap: tap,
      borderRadius: BorderRadius.circular(t.radiusTiny),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: on ? t.primary : null, borderRadius: BorderRadius.circular(t.radiusTiny)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: on ? t.onPrimary : t.text),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? t.onPrimary : t.text)),
        ]),
      ),
    );
  }

  Widget _menu<T>(BuildContext context,
      {required Key key,
      required String label,
      bool selected = false,
      bool enabled = true,
      required List<(T, String)> items,
      required void Function(T) onSelected}) {
    final t = tokensOf(context);
    return PopupMenuButton<T>(
      key: key,
      enabled: enabled,
      tooltip: '',
      color: t.surface,
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final (v, l) in items)
          PopupMenuItem<T>(
              value: v,
              child: Directionality(textDirection: TextDirection.rtl, child: Text(l, style: TextStyle(color: t.text)))),
      ],
      child: IgnorePointer(child: TechChip(label, selected: selected, dropdown: true, onTap: enabled ? () {} : null)),
    );
  }
}

/// The ⋯ menu of a tile or row.
class PcMenu extends StatelessWidget {
  final Computer pc;
  final PcActions actions;
  final bool dark;
  const PcMenu({super.key, required this.pc, required this.actions, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final state = pcStateOf(pc);
    final items = <(String, String, IconData)>[
      if (state != PcState.offline) ('connect', 'اتصال', Icons.cast_connected),
      if (state != PcState.offline && !pc.fromCache) ('demo', 'ارائه دمو', Icons.co_present_outlined),
      if (!pc.fromCache) ('open', 'باز کردن کارت', Icons.info_outline),
      if (state == PcState.offline) ('wake', 'روشن کن', Icons.power_settings_new),
      ('copy', 'کپی شناسه', Icons.copy),
    ];
    return PopupMenuButton<String>(
      tooltip: 'کارهای بیشتر',
      color: t.surface,
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_horiz, size: 18, color: t.textMuted),
      onSelected: (v) => switch (v) {
        'connect' => actions.connect(pc),
        'demo' => actions.demo(pc),
        'open' => actions.open(pc),
        'wake' => actions.wake(pc),
        _ => actions.copyId(pc),
      },
      itemBuilder: (_) => [
        for (final (v, l, i) in items)
          PopupMenuItem(
            value: v,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Row(children: [Icon(i, size: 17, color: t.textMuted), const SizedBox(width: 8), Text(l, style: TextStyle(color: t.text))]),
            ),
          ),
      ],
    );
  }
}

/// One PC as a tile: the coloured box (organization colour, white text), the Windows mark and the name; under it the
/// white strip with the ID, the dot, ★ and ⋯.
class PcTile extends StatelessWidget {
  final Computer pc;
  final PcActions actions;
  const PcTile({super.key, required this.pc, required this.actions});

  static const width = 214.0;
  static const height = 128.0;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final fill = tileColorFor(pc.organization.colorValue);
    final state = pcStateOf(pc);
    final host = (pc.hostname ?? '').trim();
    final label = (pc.label ?? '').trim();
    final title = host.isNotEmpty ? host : (label.isNotEmpty ? label : pc.rustdeskId);
    final sub = host.isNotEmpty && label.isNotEmpty ? label : '';
    return SizedBox(
      width: width,
      height: height,
      child: Material(
        color: t.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radius), side: BorderSide(color: t.line)),
        child: InkWell(
          key: ValueKey('tile-${pc.id}'),
          onTap: pc.fromCache ? null : () => actions.open(pc),
          onDoubleTap: state == PcState.offline ? null : () => actions.connect(pc),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: fill),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: _dirOf(title),
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                      if (sub.isNotEmpty)
                        Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 12)),
                      const Spacer(),
                      Text(pc.organization.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 11.5)),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  WindowsMark(size: 22, color: Colors.white.withOpacity(0.92)),
                ]),
              ),
            ),
            Container(
              height: 34,
              decoration: BoxDecoration(color: t.surface),
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: Row(children: [
                TechDot(state, size: 9),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(idFa(pc.rustdeskId),
                      textDirection: TextDirection.ltr,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: t.text)),
                ),
                _Star(pc: pc, onTap: () => actions.favorite(pc)),
                SizedBox(width: 32, child: PcMenu(pc: pc, actions: actions)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

TextDirection _dirOf(String s) => RegExp(r'[؀-ۿ]').hasMatch(s) ? TextDirection.rtl : TextDirection.ltr;

class _Star extends StatelessWidget {
  final Computer pc;
  final VoidCallback onTap;
  const _Star({required this.pc, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return IconButton(
      key: ValueKey('star-${pc.id}'),
      tooltip: pc.favorite ? 'برداشتن از علاقه‌مندی' : 'علاقه‌مندی',
      visualDensity: VisualDensity.compact,
      iconSize: 18,
      onPressed: pc.fromCache ? null : onTap,
      icon: Icon(pc.favorite ? Icons.star : Icons.star_border, color: pc.favorite ? t.warning : t.textMuted),
    );
  }
}

/// The PCs as tiles, wrapping to the window's width.
class PcTiles extends StatelessWidget {
  final List<Computer> items;
  final PcActions actions;
  final ScrollController? scroll;
  const PcTiles({super.key, required this.items, required this.actions, this.scroll});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        key: const ValueKey('pc-tiles'),
        controller: scroll,
        padding: const EdgeInsets.only(bottom: 12),
        child: Wrap(spacing: 10, runSpacing: 10, children: [for (final c in items) PcTile(pc: c, actions: actions)]),
      );
}

/// The PCs as a list (the design's table): dot, name, organization, tags, last contact, ★, actions.
class PcList extends StatelessWidget {
  final List<Computer> items;
  final PcActions actions;
  final ScrollController? scroll;
  final String? selectedId;
  const PcList({super.key, required this.items, required this.actions, this.scroll, this.selectedId});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    final head = TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.textMuted);
    return DecoratedBox(
      key: const ValueKey('pc-list'),
      decoration: BoxDecoration(
          color: t.surface, border: Border.all(color: t.line), borderRadius: BorderRadius.circular(t.radius)),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(children: [
            const SizedBox(width: 20),
            Expanded(flex: 5, child: Text('رایانه', style: head)),
            Expanded(flex: 3, child: Text('سازمان', style: head)),
            Expanded(flex: 3, child: Text('برچسب', style: head)),
            Expanded(flex: 3, child: Text('آخرین تماس', style: head)),
            const SizedBox(width: 36),
            const SizedBox(width: 200),
          ]),
        ),
        Divider(height: 1, color: t.line),
        Expanded(
          child: ListView.separated(
            controller: scroll,
            itemCount: items.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: t.line),
            itemBuilder: (context, i) => _row(context, items[i]),
          ),
        ),
      ]),
    );
  }

  Widget _row(BuildContext context, Computer pc) {
    final t = tokensOf(context);
    final state = pcStateOf(pc);
    final host = (pc.hostname ?? '').trim();
    final label = (pc.label ?? '').trim();
    final now = DateTime.now();
    final session = pc.session;
    final last = pc.fromCache
        ? ''
        : session != null
            ? (session.mine ? 'در جلسه با شما' : 'در جلسه با ${session.staffName}')
            : (pc.lastSeenAt == null ? '' : agoFa(pc.lastSeenAt!, now));
    final sub = [if (host.isNotEmpty && label.isNotEmpty) label, if (pc.shareStopped) 'اشتراک متوقف'].join(' · ');
    return Material(
      color: pc.id == selectedId ? t.surfaceAlt : t.surface,
      child: InkWell(
        key: ValueKey('row-${pc.id}'),
        onTap: pc.fromCache ? null : () => actions.open(pc),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(children: [
            SizedBox(width: 20, child: TechDot(state, size: 9)),
            Expanded(
              flex: 5,
              child: Row(children: [
                Flexible(
                  child: Text(host.isNotEmpty ? host : (label.isNotEmpty ? label : idFa(pc.rustdeskId)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: t.text)),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Flexible(child: TechHint('· $sub', maxLines: 1)),
                ],
              ]),
            ),
            Expanded(
                flex: 3,
                child: Text(pc.organization.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: t.text))),
            Expanded(
              flex: 3,
              child: Wrap(spacing: 4, runSpacing: 2, children: [for (final tag in pc.tags.take(2)) TechChip(tag, soft: true)]),
            ),
            Expanded(flex: 3, child: TechHint(last, maxLines: 1)),
            SizedBox(width: 36, child: _Star(pc: pc, onTap: () => actions.favorite(pc))),
            SizedBox(
              width: 200,
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                ..._buttons(pc, state),
                SizedBox(width: 32, child: PcMenu(pc: pc, actions: actions)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  List<Widget> _buttons(Computer pc, PcState state) {
    if (state == PcState.offline) return [TechButton('روشن کن', onPressed: () => actions.wake(pc))];
    if (state == PcState.busy) {
      return [TechButton('گرفتن جلسه', onPressed: actions.busy ? null : () => actions.connect(pc))];
    }
    return [
      TechButton('اتصال',
          key: ValueKey('connect-${pc.id}'),
          kind: TechButtonKind.primary,
          onPressed: actions.busy ? null : () => actions.connect(pc)),
      if (!pc.fromCache) ...[
        const SizedBox(width: 4),
        TechButton('دمو', onPressed: actions.busy ? null : () => actions.demo(pc)),
      ],
    ];
  }
}

/// The whole «رایانه‌ها» area: offline card, recent strip, filters, then tiles or list with their states.
class TechDashboard extends StatefulWidget {
  final DashboardController dash;
  final PcActions actions;
  final void Function(String rustdeskId) connectId;
  /// Why the portal is away (null while it answers).
  final OfflineReason? offlineReason;
  final String? selectedId;
  const TechDashboard(
      {super.key, required this.dash, required this.actions, required this.connectId, this.offlineReason, this.selectedId});

  @override
  State<TechDashboard> createState() => _TechDashboardState();
}

class _TechDashboardState extends State<TechDashboard> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) widget.dash.loadMore();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.dash,
      builder: (context, _) {
        final d = widget.dash;
        final favorites = d.items.where((c) => c.favorite).toList();
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (d.offline || widget.offlineReason != null) ...[
              TechOfflineCard(
                  reason: offlineCardText(widget.offlineReason), onRetry: d.load, lastUpdated: d.lastUpdated),
              const SizedBox(height: 10),
            ],
            TechRecentStrip(
                recent: d.recent,
                favorites: favorites,
                actions: widget.actions,
                connectId: widget.connectId,
                offline: d.offline),
            if (d.recent.isNotEmpty || favorites.isNotEmpty) const SizedBox(height: 10),
            TechFilterBar(dash: d),
            const SizedBox(height: 10),
            if (d.error != null && d.items.isNotEmpty) ...[
              TechNotice(d.error!, onClose: d.clearError),
              const SizedBox(height: 8),
            ],
            Expanded(child: _body(context, d)),
          ]),
        );
      },
    );
  }

  Widget _body(BuildContext context, DashboardController d) {
    if (d.loading && d.items.isEmpty) return const TechLoading();
    if (d.items.isEmpty) {
      if (d.error != null) {
        return TechEmpty(icon: Icons.error_outline, text: d.error!, action: 'تلاش دوباره', onAction: d.load);
      }
      final filtered = !d.query.isUnfiltered;
      return TechEmpty(
        icon: Icons.computer_outlined,
        text: filtered ? 'رایانه‌ای با این جستجو و فیلترها پیدا نشد.' : 'هنوز رایانه‌ای به دلفین وصل نشده است.',
        action: filtered ? 'برداشتن فیلترها' : null,
        onAction: filtered
            ? () {
                d.setView(PcView.all);
                d.setTag(null);
                d.setOrganization(null);
              }
            : null,
      );
    }
    final list = d.viewMode == PcViewMode.tiles
        ? PcTiles(items: d.items, actions: widget.actions, scroll: _scroll)
        : PcList(items: d.items, actions: widget.actions, scroll: _scroll, selectedId: widget.selectedId);
    return Column(children: [
      Expanded(child: list),
      if (d.loadingMore) const Padding(padding: EdgeInsets.all(6), child: TechLoading()),
    ]);
  }
}
