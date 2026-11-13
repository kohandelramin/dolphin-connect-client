import 'package:flutter/material.dart';

import '../digits.dart';
import '../tech/api.dart';
import '../tech/state.dart';
import 'format.dart';
import 'widgets.dart';

/// Plan 19 (T3): «درخواست‌ها»: در صف / مال من / بسته, a card per request with how long it has waited (amber once
/// old), and «برداشتن و تماس» in one click. «تماس‌های من» is the same list locked to mine.
String requestSource(RequestRow r) => switch (r.openedBy) {
      'app' => '«با من تماس بگیرید» از برنامه',
      'staff' => 'ثبت کارشناس',
      _ => 'از پورتال مشتری',
    };

class TechRequestsView extends StatelessWidget {
  final RequestsController requests;

  /// «تماس‌های من»: no tabs, a different title.
  final bool mineOnly;
  final void Function(RequestRow r) onTakeAndCall;
  final void Function(RequestRow r) onCall;
  final void Function(String deviceId) onOpenPc;
  final bool busy;
  final DateTime Function() now;
  const TechRequestsView({
    super.key,
    required this.requests,
    required this.onTakeAndCall,
    required this.onCall,
    required this.onOpenPc,
    this.mineOnly = false,
    this.busy = false,
    this.now = DateTime.now,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: requests,
      builder: (context, _) {
        final r = requests;
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              TechHeading(mineOnly ? 'تماس‌های من' : 'درخواست‌ها', size: 15),
              const Spacer(),
              if (!mineOnly) ...[
                TechChip('در صف ${faDigits('${r.queueCount}')}',
                    key: const ValueKey('scope-queue'),
                    selected: r.scope == RequestScope.queue,
                    onTap: () => r.setScope(RequestScope.queue)),
                const SizedBox(width: 4),
                TechChip('مال من ${faDigits('${r.mineCount}')}',
                    key: const ValueKey('scope-mine'),
                    selected: r.scope == RequestScope.mine,
                    onTap: () => r.setScope(RequestScope.mine)),
                const SizedBox(width: 4),
                TechChip('بسته',
                    key: const ValueKey('scope-closed'),
                    selected: r.scope == RequestScope.closed,
                    onTap: () => r.setScope(RequestScope.closed)),
              ],
              const SizedBox(width: 6),
              IconButton(
                  tooltip: 'تازه کردن',
                  icon: Icon(Icons.refresh, size: 18, color: tokensOf(context).textMuted),
                  onPressed: r.load),
            ]),
            const SizedBox(height: 8),
            if (r.notice != null) ...[TechNotice(r.notice!, ok: true), const SizedBox(height: 6)],
            if (r.error != null && r.rows.isNotEmpty) ...[TechNotice(r.error!), const SizedBox(height: 6)],
            Expanded(child: _body(context, r)),
          ]),
        );
      },
    );
  }

  Widget _body(BuildContext context, RequestsController r) {
    if (r.loading && r.rows.isEmpty) return const TechLoading();
    if (r.rows.isEmpty) {
      if (r.error != null) return TechEmpty(icon: Icons.error_outline, text: r.error!, action: 'تلاش دوباره', onAction: r.load);
      final text = switch (r.scope) {
        RequestScope.queue => 'صف خالی است؛ درخواستی منتظر نیست.',
        RequestScope.mine => mineOnly ? 'تماس بازی ندارید.' : 'درخواستی به نام شما نیست.',
        RequestScope.closed => 'درخواست بسته‌ای نیست.',
      };
      return TechEmpty(icon: Icons.inbox_outlined, text: text);
    }
    final n = now();
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: r.rows.length + (r.hasMore ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i >= r.rows.length) {
          return Center(child: TechButton('بیشتر', onPressed: r.loadMore));
        }
        return _card(context, r.rows[i], r.scope, n);
      },
    );
  }

  Widget _card(BuildContext context, RequestRow row, RequestScope scope, DateTime n) {
    final t = tokensOf(context);
    final closed = scope == RequestScope.closed;
    final old = !closed && isOldRequest(row.createdAt, n);
    final where = [row.organization.name, if (row.pcName != null) row.pcName!, requestSource(row)].join(' · ');
    final hasPc = row.deviceId != null && row.rustdeskId != null;
    return TechPanel(
      key: ValueKey('request-${row.id}'),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: tileColorFor(row.organization.colorValue), shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(row.subject,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w800, color: t.text)),
          ),
          if (row.urgent) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: t.dangerSoft, borderRadius: BorderRadius.circular(99)),
              child: Text('فوری', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.danger)),
            ),
            const SizedBox(width: 4),
          ],
          if (row.kind == 'demo') ...[const TechChip('دمو'), const SizedBox(width: 4)],
          if (closed)
            TechHint(row.resolvedAt == null ? '' : jalaliFa(row.resolvedAt!, n))
          else
            Container(
              key: ValueKey('wait-${row.id}'),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
              decoration: BoxDecoration(color: old ? t.warningSoft : t.surfaceAlt, borderRadius: BorderRadius.circular(99)),
              child: Text(waitedFa(row.createdAt, n),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: old ? t.warning : t.text)),
            ),
        ]),
        const SizedBox(height: 2),
        TechHint('#${faDigits('${row.number}')} · $where', maxLines: 1),
        if (row.contactName != null || row.contactPhone != null || row.assigneeName != null)
          Row(children: [
            if (row.contactName != null) TechHint(row.contactName!),
            if (row.contactPhone != null) ...[
              const TechHint(' · '),
              Text(row.contactPhone!, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: t.textMuted)),
            ],
            if (row.assigneeName != null && !row.mine) TechHint(' · با ${row.assigneeName}'),
          ]),
        if (!closed) ...[
          const SizedBox(height: 6),
          Row(children: [
            if (scope == RequestScope.queue)
              TechButton('برداشتن و تماس',
                  key: ValueKey('take-${row.id}'),
                  kind: TechButtonKind.primary,
                  onPressed: busy ? null : () => onTakeAndCall(row))
            else if (hasPc)
              TechButton('تماس', key: ValueKey('call-${row.id}'), kind: TechButtonKind.primary, onPressed: busy ? null : () => onCall(row)),
            const SizedBox(width: 6),
            if (row.deviceId != null) TechButton('دیدن', onPressed: () => onOpenPc(row.deviceId!)),
          ]),
        ],
      ]),
    );
  }
}
