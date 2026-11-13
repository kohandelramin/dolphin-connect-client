import 'package:flutter/material.dart';

import '../tech/actions.dart';
import '../tech/api.dart';
import '../tech/state.dart';
import 'code_wait.dart';
import 'format.dart';
import 'widgets.dart';

/// Plan 19 (T2): the PC's card as a drawer beside the list: everything the web's «رایانه‌ها» and PC page had, in one
/// place: the PC, «اتصال» / «ارائه دمو» / ★, the open call (reason chips, internal note, «پیام به مشتری», «پایان
/// تماس»), code mode's wait for the customer's code, «فرستاده‌ی مشتری» and «آخرین تماس‌ها».
const kWaitingForCode = 'در انتظار کد مشتری…';
const kWaitingForCodeHint = 'مشتری کد را در پورتال وارد می‌کند؛ کد که برسد، خودکار وصل می‌شود. اگر کد را تلفنی گفت، اینجا بنویسید.';

class TechPcCard extends StatefulWidget {
  final PcCardController card;
  final List<CallReason> reasons;
  final VoidCallback onClose;
  final void Function(PcRef pc) onConnect;
  final void Function(PcRef pc) onDemo;
  final void Function(PcRef pc) onEndCall;
  final void Function(SentItem item) onDownload;
  final void Function(String deviceId) onWake;

  /// A session opened with the customer's code (the shell remembers it for RO-8).
  final void Function(ConnectOutcome o, PcRef pc)? onCodeOutcome;
  final bool busy;
  final bool offline;
  final Duration codePoll;
  const TechPcCard({
    super.key,
    required this.card,
    required this.reasons,
    required this.onClose,
    required this.onConnect,
    required this.onDemo,
    required this.onEndCall,
    required this.onDownload,
    required this.onWake,
    this.onCodeOutcome,
    this.busy = false,
    this.offline = false,
    this.codePoll = const Duration(seconds: 3),
  });

  static const width = 380.0;

  @override
  State<TechPcCard> createState() => _TechPcCardState();
}

class _TechPcCardState extends State<TechPcCard> {
  final _note = TextEditingController();
  final _code = TextEditingController();
  late CodeModeWatcher _watcher;

  @override
  void initState() {
    super.initState();
    _watcher = _watch(widget.card);
  }

  CodeModeWatcher _watch(PcCardController c) => CodeModeWatcher(c, every: widget.codePoll, onOutcome: (o) {
        final d = c.detail;
        if (d != null) widget.onCodeOutcome?.call(o, PcRef.of(d.computer));
      });

  @override
  void didUpdateWidget(TechPcCard old) {
    super.didUpdateWidget(old);
    if (!identical(old.card, widget.card)) {
      _watcher.dispose();
      _watcher = _watch(widget.card);
      _note.clear();
      _code.clear();
    }
  }

  @override
  void dispose() {
    _watcher.dispose();
    _note.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Container(
      key: const ValueKey('tech-pc-card'),
      width: TechPcCard.width,
      decoration: BoxDecoration(color: t.surface, border: BorderDirectional(end: BorderSide(color: t.line))),
      child: ListenableBuilder(
        listenable: widget.card,
        builder: (context, _) {
          final c = widget.card;
          final d = c.detail;
          if (d == null) {
            return Column(children: [
              _closeRow(context, null),
              Expanded(
                child: c.loading || c.error == null
                    ? const TechLoading()
                    : TechEmpty(icon: Icons.error_outline, text: c.error!, action: 'تلاش دوباره', onAction: c.load),
              ),
            ]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _closeRow(context, d),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), children: _body(context, c, d)),
            ),
          ]);
        },
      ),
    );
  }

  Widget _closeRow(BuildContext context, ComputerDetail? d) {
    final t = tokensOf(context);
    final pc = d?.computer;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 14, end: 4, top: 6),
      child: Row(children: [
        if (pc != null) ...[
          Expanded(
            child: Text(pc.hostname?.trim().isNotEmpty == true ? pc.hostname!.trim() : pc.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: t.text)),
          ),
          TechDot(pcStateOf(pc)),
          const SizedBox(width: 4),
        ] else
          const Spacer(),
        IconButton(
            key: const ValueKey('tech-card-close'),
            tooltip: 'بستن',
            icon: Icon(Icons.close, size: 18, color: t.textMuted),
            onPressed: widget.onClose),
      ]),
    );
  }

  List<Widget> _body(BuildContext context, PcCardController c, ComputerDetail d) {
    final t = tokensOf(context);
    final pc = d.computer;
    final ref = PcRef.of(pc);
    final state = pcStateOf(pc);
    final now = DateTime.now();
    final label = (pc.label ?? '').trim();
    final chips = <Widget>[
      for (final tag in d.tags.isNotEmpty ? d.tags : pc.tags) TechChip(tag, soft: true),
      if (osFa(pc.os).isNotEmpty) TechChip(osFa(pc.os)),
      if (appVersionFa(d.clientVersion ?? pc.dolphinVersion).isNotEmpty) TechChip(appVersionFa(d.clientVersion ?? pc.dolphinVersion)),
      if (d.consentMode == ConsentMode.code) const TechChip('با کد یک‌بار مصرف'),
    ];
    final call = d.call;
    final waiting = _watcher.waiting || c.waitingForCode != null || (call?.waitingForCode ?? false);
    final busy = widget.busy || c.busy;
    return [
      Row(children: [
        Flexible(child: TechHint([pc.organization.name, if (label.isNotEmpty) label].join(' · '))),
        const TechHint(' · '),
        Text(idFa(pc.rustdeskId), textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: t.textMuted)),
      ]),
      if (d.customerName != null || d.ownerName != null)
        TechHint([if (d.customerName != null) d.customerName!, if (d.ownerName != null) 'کاربر: ${d.ownerName}'].join(' · ')),
      if (pc.session != null)
        TechHint(pc.session!.mine ? 'در جلسه با شما' : 'در جلسه با ${pc.session!.staffName}', color: t.warning),
      const SizedBox(height: 6),
      if (chips.isNotEmpty) Wrap(spacing: 4, runSpacing: 4, children: chips),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: state == PcState.offline
              ? TechButton('روشن کن', expand: true, icon: Icons.power_settings_new, onPressed: () => widget.onWake(pc.id))
              : TechButton(state == PcState.busy ? 'گرفتن جلسه' : 'اتصال',
                  key: const ValueKey('tech-card-connect'),
                  expand: true,
                  kind: TechButtonKind.primary,
                  onPressed: busy ? null : () => widget.onConnect(ref)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: TechButton('ارائه دمو',
              key: const ValueKey('tech-card-demo'),
              expand: true,
              onPressed: busy || widget.offline || state == PcState.offline ? null : () => widget.onDemo(ref)),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message: pc.favorite ? 'برداشتن از علاقه‌مندی' : 'علاقه‌مندی',
          child: TechButton('',
              key: const ValueKey('tech-card-star'),
              icon: pc.favorite ? Icons.star : Icons.star_border,
              onPressed: busy ? null : c.toggleFavorite),
        ),
      ]),
      if (c.error != null) ...[const SizedBox(height: 8), TechNotice(c.error!)],
      if (c.notice != null) ...[const SizedBox(height: 8), TechNotice(c.notice!, ok: true)],
      if (waiting) ...[const SizedBox(height: 10), _codeBox(context, c)],
      _sep(context),
      if (call != null) ..._callBox(context, c, call, ref) else TechHint('تماس بازی با این رایانه ندارید. «اتصال» تماس را باز می‌کند.'),
      _sep(context),
      const TechHeading('فرستاده‌ی مشتری'),
      const SizedBox(height: 4),
      if (d.sentToday.isEmpty)
        const TechHint('امروز چیزی نفرستاده است.')
      else
        for (final s in d.sentToday) _sentRow(context, s, now),
      const SizedBox(height: 12),
      const TechHeading('آخرین تماس‌ها'),
      const SizedBox(height: 4),
      if (d.history.isEmpty)
        const TechHint('هنوز تماسی ثبت نشده است.')
      else
        for (final h in d.history.take(8)) TechHint(historyLine(h, now)),
    ];
  }

  Widget _sep(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Divider(height: 1, color: tokensOf(context).line));

  Widget _codeBox(BuildContext context, PcCardController c) {
    final t = tokensOf(context);
    return Container(
      key: const ValueKey('tech-card-code'),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.surfaceAlt, borderRadius: BorderRadius.circular(t.radiusSmall)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: t.primaryText)),
          const SizedBox(width: 8),
          Text(kWaitingForCode, style: TextStyle(fontWeight: FontWeight.w800, color: t.primaryText)),
        ]),
        const SizedBox(height: 4),
        Text(kWaitingForCodeHint, style: TextStyle(fontSize: 12, height: 1.6, color: t.text)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              key: const ValueKey('tech-card-code-field'),
              controller: _code,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.center,
              style: TextStyle(color: t.text, fontSize: 13),
              decoration: techField(context, hint: 'کد مشتری'),
              onSubmitted: (_) => _sendCode(),
            ),
          ),
          const SizedBox(width: 6),
          TechButton('اتصال با کد', kind: TechButtonKind.primary, onPressed: c.busy ? null : _sendCode),
        ]),
      ]),
    );
  }

  Future<void> _sendCode() async {
    final text = _code.text.trim();
    if (text.isEmpty) return;
    final o = await _watcher.typed(text);
    if (o is Connected) _code.clear();
  }

  List<Widget> _callBox(BuildContext context, PcCardController c, OpenCall call, PcRef ref) {
    final t = tokensOf(context);
    final now = DateTime.now();
    return [
      Row(children: [
        const TechHeading('تماس باز'),
        const Spacer(),
        if (call.sessionLive)
          TechHint(call.connectedSince == null ? 'جلسه وصل است' : 'وصل از ${clockFa(call.connectedSince!)} · ${elapsedFa(now.difference(call.connectedSince!))}',
              color: t.success),
      ]),
      if (call.contactName != null || call.contactPhone != null)
        Row(children: [
          Flexible(child: TechHint([if (call.contactName != null) call.contactName!].join(' · '))),
          if (call.contactPhone != null) ...[
            const TechHint(' · '),
            Text(call.contactPhone!, textDirection: TextDirection.ltr, style: TextStyle(fontSize: 12, color: t.textMuted)),
          ],
        ]),
      const SizedBox(height: 6),
      if (widget.reasons.isNotEmpty)
        Wrap(spacing: 4, runSpacing: 4, children: [
          for (final r in widget.reasons)
            TechChip(r.name,
                key: ValueKey('reason-${r.id}'),
                selected: call.reasonId == r.id,
                onTap: c.busy ? null : () => c.setReason(call.reasonId == r.id ? null : r.id)),
        ]),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('tech-card-note'),
        controller: _note,
        minLines: 2,
        maxLines: 4,
        style: TextStyle(color: t.text, fontSize: 13),
        decoration: techField(context, hint: 'یادداشت داخلی… (مشتری نمی‌بیند)'),
      ),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        TechButton('ثبت یادداشت',
            onPressed: c.busy
                ? null
                : () async {
                    if (_note.text.trim().isEmpty) return;
                    if (await c.addNote(_note.text)) _note.clear();
                  }),
        TechButton('پیام به مشتری', key: const ValueKey('tech-card-message'), onPressed: c.busy ? null : () => _message(context, c)),
        TechButton('پایان تماس',
            key: const ValueKey('tech-card-end'), kind: TechButtonKind.danger, onPressed: c.busy ? null : () => widget.onEndCall(ref)),
      ]),
    ];
  }

  Future<void> _message(BuildContext context, PcCardController c) async {
    final text = await showDialog<String>(context: context, builder: (_) => const TechMessageDialog());
    if (text != null && text.trim().isNotEmpty) await c.sendMessage(text);
  }

  Widget _sentRow(BuildContext context, SentItem s, DateTime now) {
    final t = tokensOf(context);
    final kind = s.kind == 'screenshot' ? 'عکس صفحه' : (s.kind == 'report' ? 'گزارش رایانه' : s.kind);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(children: [
        Icon(s.kind == 'screenshot' ? Icons.image_outlined : Icons.description_outlined, size: 16, color: t.textMuted),
        const SizedBox(width: 6),
        Expanded(
          child: TechHint(
              '$kind · ${dayTimeFa(s.createdAt, now)} · ${sizeFa(s.size)}${s.note == null || s.note!.trim().isEmpty ? '' : ' — «${s.note!.trim()}»'}',
              maxLines: 2),
        ),
        TechButton('دریافت', kind: TechButtonKind.quiet, onPressed: () => widget.onDownload(s)),
      ]),
    );
  }
}

/// One line of «آخرین تماس‌ها»: «خطای چاپ فاکتور · ۶ آبان · علی · حل‌شده», «اتصال · دیروز · علی · ۱۲ دقیقه».
String historyLine(HistoryEntry h, DateTime now) {
  switch (h) {
    case HistoryRequest():
      final status = switch (h.status) {
        'resolved' || 'closed' => 'حل‌شده',
        'open' || 'new' => 'باز',
        'in_progress' || 'assigned' => 'در دست کار',
        _ => h.status,
      };
      return [h.subject, jalaliFa(h.at, now), if (h.assigneeName != null) h.assigneeName!, status].join(' · ');
    case HistoryConnection():
      final minutes = h.closedAt?.difference(h.at).inMinutes;
      return [
        'اتصال',
        dayTimeFa(h.at, now),
        if (h.technician != null) h.technician!,
        if (minutes != null) (minutes < 1 ? 'کمتر از یک دقیقه' : '${idFaNum(minutes)} دقیقه'),
        if (h.files > 0) '${idFaNum(h.files)} فایل',
      ].join(' · ');
  }
}

String idFaNum(int n) => n.toString().replaceAllMapped(RegExp(r'[0-9]'), (m) => '۰۱۲۳۴۵۶۷۸۹'[int.parse(m[0]!)]);

/// «پیام به مشتری»: one short text the customer reads in the portal and the app.
class TechMessageDialog extends StatefulWidget {
  const TechMessageDialog({super.key});

  @override
  State<TechMessageDialog> createState() => _TechMessageDialogState();
}

class _TechMessageDialogState extends State<TechMessageDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        backgroundColor: t.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusLarge)),
        title: Text('پیام به مشتری', style: TextStyle(color: t.text, fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 360,
          child: TextField(
            key: const ValueKey('tech-message-text'),
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 1000,
            style: TextStyle(color: t.text),
            decoration: techField(context, hint: 'مشتری این پیام را می‌بیند.'),
          ),
        ),
        actions: [
          TechButton('انصراف', kind: TechButtonKind.quiet, onPressed: () => Navigator.of(context).pop()),
          TechButton('فرستادن',
              key: const ValueKey('tech-message-send'),
              kind: TechButtonKind.primary,
              onPressed: () => Navigator.of(context).pop(_text.text)),
        ],
      ),
    );
  }
}
